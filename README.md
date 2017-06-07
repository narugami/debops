# Debops

Post a daily summary of Fitbit to Slack

![Deb](http://i.imgur.com/LyDV747.png)

## How to deploy

```
# Install Heroku Toolbelt
brew install heroku-toolbelt
heroku login

git clone https://github.com/narugami/debops.git
cd debops
heroku create

git push heroku master

heroku addons:add scheduler:standard
heroku addons:create memcachier:dev

# Get from https://api.slack.com/incoming-webhooks
heroku config:set WEBHOOK_URL=https://hooks.slack.com/services/xxxx

# Get from https://dev.fitbit.com/apps/oauthinteractivetutorial
# See http://qiita.com/makopo/items/32f41128c2e055cec68f
# Flow type: [Authorization Code Flow]
# OAuth 2.0 Application Type: [Personal]
# Expires In(ms): [31536000]
heroku config:set FITBIT_CLIENT_ID=hoge FITBIT_CLIENT_SECRET=huga
heroku run "bundle exec ruby main.rb --setup --access_token foo --refresh_token bar"

# Click [Add new job] and type [[$]bundle exec ruby main.rb]
heroku config:add TZ=Asia/Tokyo
heroku addons:open scheduler
```
