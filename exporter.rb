require 'selenium-webdriver'
require 'nokogiri'
require 'io/console'
require 'yaml'
require 'byebug'

def finishLoading(browser, wait)
  begin
    browser.find_element(:xpath, "//div[contains(@class, 'LoaderNew---overlay')]").displayed?
  rescue Selenium::WebDriver::Error::NoSuchElementError, Selenium::WebDriver::Error::StaleElementReferenceError
    return
  end

  wait.until do
    browser.find_elements(:xpath, "//div[contains(@class, 'LoaderNew---overlay')]").empty?
  end
end

def sanitize_td(text)
  text.split('  ').map(&:strip).reject(&:empty?).join(' ')
end

def retryable_click(element)
  element.click
rescue Selenium::WebDriver::Error::ElementClickInterceptedError
  element.click # retry once
end

def parse_table(browser, wait, days, type, first = true, transactions = [], page = 1)
  if first && type == :accounts
    puts "Looking for #{days} days of transactions ..."
    finishLoading(browser, wait)
    wait.until do
      browser.find_element(:id, 'daysType').displayed?
    end
    retryable_click(browser.find_element(:id, 'daysType'))
    wait.until do
      browser.find_element(:xpath, "//span[text()='Last #{days} days']").displayed?
    end
    retryable_click(browser.find_element(:xpath, "//span[text()='Last #{days} days']"))
  end

  finishLoading(browser, wait)
  wait.until do
    browser.find_element(:xpath, '//table').displayed?
  end
  puts "Parsing page #{page} ..."
  table_html = browser.find_element(:xpath, '//table').attribute('innerHTML')
  html_doc = Nokogiri::HTML(table_html)
  html_doc.search('tr').each do |tr|
    tds = tr.search('td')
    next unless tds.length > 0

    sign = /negativeAmount/.match(tds[3].inner_html) ? -1 : 1
    date = Date.parse(sanitize_td(tds[0].text))

    transactions << {
      date: date.to_s,
      memo: sanitize_td(tds[1].text),
      amount: sign * sanitize_td(tds[3].text).gsub(/RM|,/, '').to_f
    }

    next_button = begin
      browser.find_element(:xpath, "//a[contains(@class, 'next_arrow')]")
    rescue Selenium::WebDriver::Error::NoSuchElementError
      nil
    end

    next unless next_button

    wait.until do
      next_button.displayed?
    end
    retryable_click(next_button)
    page += 1
    parse_table(browser, wait, days, type, false, transactions, page)
  end

  transactions
end

def export_to_file(browser, wait, acc_name, days, type)
  puts "Exporting #{acc_name} transactions ..."
  finishLoading(browser, wait)
  if type == :accounts
    retryable_click(browser.find_element(:xpath, "//div[text()='ACCOUNTS']"))
  elsif type == :cards
    retryable_click(browser.find_element(:xpath, "//div[text()='CARDS']"))
  end
  finishLoading(browser, wait)
  retryable_click(browser.find_element(:xpath, "//span[text()='#{acc_name}']"))
  transactions = parse_table(browser, wait, days, type).sort_by { |t| t[:date] }
  puts 'Done parsing tables ...'

  f = File.open("exports/#{acc_name}.qif", 'w')
  transactions.each do |t|
    trx = <<~TRX
      !Type:Bank
      D#{t[:date]}
      T#{t[:amount]}
      M#{t[:memo]}
      ^
    TRX
    f.write(trx)
  end
  f.close

  puts "Exported #{transactions.count} transactions ..."
end

# ===========

printf 'Username: '
username = ENV['VERBOSE'] ? gets.chomp : STDIN.noecho(&:gets).chomp
printf "\nPassword: "
password = ENV['VERBOSE'] ? gets.chomp : STDIN.noecho(&:gets).chomp

puts "\nLaunching website ..."
wait = Selenium::WebDriver::Wait.new(timeout: 60)
options = Selenium::WebDriver::Chrome::Options.new
options.headless! unless ENV['HEAD'] # remove to debug
browser = Selenium::WebDriver.for(:chrome, options: options)
browser.manage.window.resize_to(1024, 768)
browser.navigate.to 'https://www.maybank2u.com.my/home/m2u/common/login.do'

wait.until do
  browser.find_element(:id, 'username').displayed?
end

puts 'Entering username ...'
browser.find_element(:id, 'username').send_keys username
retryable_click(browser.find_element(:name, 'button'))

puts 'Verification image loaded ...' if wait.until do
  browser.find_element(:class, 'btn-success').displayed?
end

# puts "Is the verification image correct? [Y/n]: "
# answer = gets.chomp
# raise "Invalid verification image!" if answer != "Y"

retryable_click(browser.find_element(:class, 'btn-success'))

wait.until do
  browser.find_element(:id, 'my-password-input').displayed?
end

puts 'Entering password ...'
browser.find_element(:id, 'my-password-input').send_keys password
retryable_click(browser.find_element(:class, 'btn-success'))

puts 'Successful login' if wait.until do
  /Your last login was on/.match(browser.page_source)
end

to_import = YAML.load_file('accounts.yml')

accounts = to_import['accounts']
accounts.each do |acc|
  export_to_file(browser, wait, acc['name'], acc['days'], :accounts)
end

cards = to_import['cards']
cards.each do |acc|
  export_to_file(browser, wait, acc['name'], 0, :cards)
end

puts 'Done!!!'

browser.quit
