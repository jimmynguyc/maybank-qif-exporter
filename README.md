Export Maybank transactions into QIF files

# Disclaimer
The developer(s) assume no liability and are not responsible for any misuse or damage caused by this program. Use at your own risk.

# How to use

1. Download Chrome webdriver https://chromedriver.storage.googleapis.com/index.html (find same version with installed Chrome) and add to $PATH directories (e.g. `/usr/local/bin`)

2. Change `accounts.yml`

3. Run `exporter.rb`
```bash
$ bundle install
$ bundle exec ruby exporter.rb                                                                                                                                    [16:36:34]
Username: 
Password:
```

# Important Notes

1. Running it too frequently may trigger password reset.
2. Made to work with M2U personnal account as of 11 Oct 2021. Future updates on UI may break code.
3. Works on macOS Big Sur & Chrome 94.0.4606.81 & ChromeDriver 94.0.4606.61, might not work with different setup. PR welcomed.
