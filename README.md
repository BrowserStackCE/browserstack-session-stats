# browserstack_session_stats
This repository helps analyse the BrowserStack Automate test sessions for any latency issues

## How to use?

- Ensure you have [Ruby](https://www.ruby-lang.org/en/downloads/) (2.x or 3.x) setup on your machine.

- Run analysis for a particular test session
```
BROWSERSTACK_USERNAME=<YOUR_BROWSERSTACK_USERNAME> BROWSERSTACK_ACCESS_KEY=<YOUR_BROWSERSTACK_ACCESS_KEY> ruby fetch_bstack_session_stats.rb session <BROWSERSTACK_SESSION_ID>
```

- Run analysis for an entire test build
```
BROWSERSTACK_USERNAME=<YOUR_BROWSERSTACK_USERNAME> BROWSERSTACK_ACCESS_KEY=<YOUR_BROWSERSTACK_ACCESS_KEY> ruby fetch_bstack_session_stats.rb build <BROWSERSTACK_BUILD_ID>
```

- In case, you would like to tailor the thresholds for inside_time, outside_time, session_stop_time, please update the same in config.yml in seconds.

- Inside time for each Selenium command is defined as the time taken to process the command by BrowserStack, as logged in Test session's Raw logs. i.e.
```
(current command's response time) minus (current command's request time)
```

- Outside time for each Selenium command is defined as the time taken required to receive the next command from the user's infrastructure after BrowserStack has sent the previous command's response, as logged in Test session's Raw logs. i.e.
```
(current command's request time) minus (previous command's response time)
```

- Session stop time for each Selenium session is defined as the time difference between the final Selenium command response time and the SESSION_STOP_TIME, as logged in Test session's Raw logs. i.e.
```
(STOP_SESSION command log time) minus (previous command's response time)
```
Note: Based on current logging in the Raw logs, the duration of the stop session is a factor of both user infrastructure and BrowserStack processing time. 
