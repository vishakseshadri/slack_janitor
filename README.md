# slack_janitor
A ruby script to auto-archive Slack channels. Works with public channels but the Slack app will need to be invited to a private channel to archive them too.
Available Dry Run mode, with the options to provide an allowlist and archivelist as well.
The channel names mentioned in allowlist.txt will not be archived even if it meets criteria
If there are any channels in archivelist.txt, only they will be checked for archival.

Originally looked into https://github.com/Symantec/slack-autoarchive but it had some issues which were easier to fix by rewriting in Ruby. 

## Requirements
* Ruby 2.7.1
* Slack App with the following Scopes:
  * [channels:history](https://api.slack.com/scopes/channels:history)
  * [channels:join](https://api.slack.com/scopes/channels:join)
  * [channels:manage](https://api.slack.com/scopes/channels:manage)
  * [channels:read](https://api.slack.com/scopes/channels:read)
  * [chat:write](https://api.slack.com/scopes/chat:write)
  * [chat:write.public](https://api.slack.com/scopes/chat:write.public)
  * [groups:history](https://api.slack.com/scopes/groups:history)
  * [groups:read](https://api.slack.com/scopes/groups:read)
  * [groups:write](https://api.slack.com/scopes/groups:write)
* Clone this repo down
* Run `bundle install`

## Example Usages
The  `BOT_TOKEN`  must be exposed as a environment variable before running your script. By default, the script will do a  `DRY_RUN`. To perform a non-dry run, specify  `-d false` on your command line. See sample usages below.

```
# Helper output
ruby janitor.rb -h                                                                
Usage: example.rb [options]
    -d, --dryrun <true/false>        Set Dry Run to true or false. Defaults to true
    -h, --help                       Prints this help

# Run the script in dry run archive mode...This will output a list of channels that will be archived.
BOT_TOKEN=<TOKEN> ruby janitor.rb

# Run the script in active archive mode...THIS WILL ARCHIVE CHANNELS!
BOT_TOKEN=<TOKEN> ruby janitor.rb -d false
```

## Options
1. Run `ruby janitor.rb -h` to print out help
2. Run `ruby janitor.rb` to run in Dry Run mode. No channels will be archived, but a soon to archive message will be posted on applicable channels
3. Run `ruby janitor.rb -d false` to run in Live mode. Channels will be archived after a message is posted on the channel.

## How can I exempt my channel from being archived?
You can add the string '%noarchive' to your channel purpose or topic. (There is also an allowlist file if you prefer.)

## How can I limit which channels to archive?
There is an archivelist file you can add channels to and the script will only check those channels.

## What Channels Will Be Archived
A channel will be archived by this script is it doesn't meet any of the following criteria:
-   Has non-bot messages in the past 60 days (configurable via an env variable)
-   Is in an allowlist. A channel is considered to be in an allowlist if the channel name is provided in an allowlist.txt file or if the channel topic or purpose has the keyword `noarchive`

## What Happens When A Channel Is Archived By This Script
-   *Don't panic! It can be unarchived by following  [these instructions](https://get.slack.help/hc/en-us/articles/201563847-Archive-a-channel#unarchive-a-channel)  However all previous members would be kicked out of the channel and not be automatically invited back.
-   A message will be dropped into the channel saying the channel is being auto archived because of low activity
-   You can always keep a channel in an allowlist if it indeed needs to be kept despite meeting the auto-archive criteria.

PRs welcome!
