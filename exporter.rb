require "selenium-webdriver"
require "nokogiri"
require "io/console"
require "yaml"
require "byebug"

def finishLoading(browser, wait)
  begin
    browser.find_element(:xpath, "//div[contains(@class, 'LoaderNew---overlay')]").displayed?
  rescue Selenium::WebDriver::Error::NoSuchElementError, Selenium::WebDriver::Error::StaleElementReferenceError
    return
  end

  wait.until {
    browser.find_elements(:xpath, "//div[contains(@class, 'LoaderNew---overlay')]").empty?
  }
end

def sanitize_td(text)
  text.split("  ").map(&:strip).reject(&:empty?).join(" ")
end

def retryable_click(element)
  begin
    element.click
  rescue Selenium::WebDriver::Error::ElementClickInterceptedError
    element.click # retry once
  end
end

def parse_table(browser, wait, days, type, first = true, transactions = [], page = 1)
  if first && type == :accounts
    puts "Looking for #{days} days of transactions ..."
    finishLoading(browser, wait)
    wait.until {
      browser.find_element(:id, "daysType").displayed?
    }
    retryable_click(browser.find_element(:id, "daysType"))
    wait.until {
      browser.find_element(:xpath, "//span[text()='Last #{days} days']").displayed?
    }
    retryable_click(browser.find_element(:xpath, "//span[text()='Last #{days} days']"))
  end

  finishLoading(browser, wait)
  wait.until {
    browser.find_element(:xpath, "//table").displayed?
  }
  puts "Parsing page #{page} ..."
  table_html = browser.find_element(:xpath, "//table").attribute("innerHTML")
  html_doc = Nokogiri::HTML(table_html)
  html_doc.search("tr").each do |tr|
    tds = tr.search("td")
    next unless tds.length > 0

    sign = /negativeAmount/.match(tds[3].inner_html) ? -1 : 1
    date = Date.parse(sanitize_td(tds[0].text))

    transactions << {
      date: date.to_s,
      memo: sanitize_td(tds[1].text),
      amount: sign * sanitize_td(tds[3].text).gsub(/RM|,/, "").to_f,
    }

    next_button = begin
        browser.find_element(:xpath, "//a[contains(@class, 'next_arrow')]")
      rescue Selenium::WebDriver::Error::NoSuchElementError
        nil
      end

    if next_button
      wait.until {
        next_button.displayed?
      }
      retryable_click(next_button)
      page += 1
      parse_table(browser, wait, days, type, false, transactions, page)
    end
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
  puts "Done parsing tables ..."

  f = File.open("exports/#{acc_name}.qif", "w")
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

printf "Username: "
username = STDIN.noecho(&:gets).chomp
printf "\nPassword: "
password = STDIN.noecho(&:gets).chomp

puts "\nLaunching website ..."
wait = Selenium::WebDriver::Wait.new(:timeout => 60)
options = Selenium::WebDriver::Chrome::Options.new
options.headless! # remove to debug
browser = Selenium::WebDriver.for(:chrome, options: options)
browser.manage.window.resize_to(1024, 768)
browser.navigate.to "https://www.maybank2u.com.my/home/m2u/common/login.do"

wait.until {
  browser.find_element(:id, "username").displayed?
}

puts "Entering username ..."
browser.find_element(:id, "username").send_keys username
retryable_click(browser.find_element(:name, "button"))

puts "Verification image loaded ..." if wait.until {
  browser.find_element(:class, "btn-success").displayed?
}

# puts "Is the verification image correct? [Y/n]: "
# answer = gets.chomp
# raise "Invalid verification image!" if answer != "Y"

retryable_click(browser.find_element(:class, "btn-success"))

wait.until {
  browser.find_element(:id, "my-password-input").displayed?
}

puts "Entering password ..."
browser.find_element(:id, "my-password-input").send_keys password
retryable_click(browser.find_element(:class, "btn-success"))

puts "Successful login" if wait.until {
  /Your last login was on/.match(browser.page_source)
}

to_import = YAML.load_file("accounts.yml")

accounts = to_import["accounts"]
accounts.each do |acc|
  export_to_file(browser, wait, acc["name"], acc["days"], :accounts)
end

cards = to_import["cards"]
cards.each do |acc|
  export_to_file(browser, wait, acc["name"], 0, :cards)
end

puts "Done!!!"

browser.quit
