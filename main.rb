require 'bundler'
Bundler.require
Dotenv.load

require "active_support/all"
require 'optparse'
require 'json'

dc = Dalli::Client.new((ENV['MEMCACHIER_SERVERS'] || 'localhost').split(','),
  {:username => ENV['MEMCACHIER_USERNAME'],
   :password => ENV['MEMCACHIER_PASSWORD'],
   :failover => true,
   :socket_timeout => 1.5,
   :socket_failure_delay => 0.2
  })

options = {}
OptionParser.new do |opt|
  opt.on('--setup') {|v| options[:setup] = true}
  opt.on('--access_token VALUE') {|v| options[:access_token] = v }
  opt.on('--refresh_token VALUE') {|v| options[:refresh_token] = v }
  opt.parse!(ARGV)
end

if options[:setup]
  dc.set('access_token', options[:access_token])
  dc.set('refresh_token', options[:refresh_token])
  puts "Set access_token: #{dc.get(:access_token)}"
  puts "Set refresh_token: #{dc.get(:refresh_token)}"
  exit 0
end

module Fitbit
  class Client
    def food_logs(user_id: '-', date: Date.today)
      get("#{API_URI}/user/#{user_id}/foods/log/date/#{date}.json")
    end
  end
end

$current = {}, $prev = {}

def f(value, unit = '')
  (value.is_a?(Float) ? value.round(2) : value).to_s(:delimited) + unit
end

def f_cur(key, unit = '')
  f($current[key], unit)
end

def f_sleep(key)
  "#{($current[key] / 60).floor}時間#{($current[key] % 60).floor}分"
end

def f_diff(key, unit = '')
  if $prev[key]
    diff = $current[key] - $prev[key]
    "(#{diff > 0 ? '+' : ''}#{f(diff, unit)})"
  end
end

client = Fitbit::Client.new(
  client_id: ENV['FITBIT_CLIENT_ID'],
  client_secret: ENV['FITBIT_CLIENT_SECRET'],
  token: dc.get('access_token'),
  refresh_token: dc.get('refresh_token'),
  expires_at: Time.now + 10.years
  )
client.refresh!

YESTERDAY = Date.today.yesterday.strftime('%Y-%m-%d')
weight = client.weight_logs(date: YESTERDAY)['weight'].min {|a, b| a['weight'] <=> b['weight']}
activity_summary = client.activity(date: YESTERDAY)['summary']
sleep_summary = client.sleep_logs(date: YESTERDAY)['summary']
food_summary = client.food_logs(date: YESTERDAY)['summary']

dc.set('access_token', client.access_token.token)
dc.set('refresh_token', client.access_token.refresh_token)

$current = {
  bmi: weight['bmi'],
  fat: weight['fat'],
  weight: weight['weight'],
  weight_without_fat: weight['weight'] * (1 - (weight['fat'] / 100.0)),
  calories_in: food_summary['calories'],
  calories_out: activity_summary['caloriesOut'],
  steps: activity_summary['steps'],
  distance: activity_summary['distances'].find {|x| x['activity'] == 'total'}['distance'],
  total_minutes_asleep: sleep_summary['totalMinutesAsleep'],
  total_time_in_bed: sleep_summary['totalTimeInBed'],
}

[:bmi, :fat, :weight, :weight_without_fat, :calories_in, :calories_out].each { |x|
  $prev[x] = dc.get("prev_#{x}")
  dc.set("prev_#{x}", $current[x])
}

notifier = Slack::Notifier.new ENV['WEBHOOK_URL'] , username: 'DebOps', icon_emoji: ':hamburger:'
notifier.ping <<"EOS"
==#{YESTERDAY}の活動情報==
体重: #{f_cur(:weight, 'kg')}　#{f_diff(:weight, 'kg')}
BMI: #{f_cur(:bmi)}　#{f_diff(:bmi)}
除脂肪体重: #{f_cur(:weight_without_fat, 'kg')}　#{f_diff(:weight_without_fat, 'kg')}
体脂肪率: #{f_cur(:fat, '%')}　#{f_diff(:fat, '%')}

摂取カロリー: #{f_cur(:calories_in, 'kcal')}　#{f_diff(:calories_in, 'kcal')}
消費カロリー: #{f_cur(:calories_out, 'kcal')}　#{f_diff(:calories_out, 'kcal')}

睡眠時間: #{f_sleep(:total_minutes_asleep)}　(就寝時間: #{f_sleep(:total_time_in_bed)})
歩行距離: #{f_cur(:distance, 'km')}　(#{f_cur(:steps, '歩')})
EOS
