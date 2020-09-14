# frozen_string_literal:true

require 'dotenv'
require 'date'
require 'optparse'
require 'slack-ruby-client'
require 'wannabe_bool'

Dotenv.load

class ChannelReaper
  attr_accessor :archive_candidates, :dry_run, :days_inactive,
                :allowlist, :archivelist, :subtypes, :retry_delay

  def initialize(dry_run)
    @archive_candidates = {}
    @dry_run = dry_run.to_bool
    @days_inactive = ENV['DAYS_INACTIVE'].nil? ? ENV['DAYS_INACTIVE'].to_i : 60
    allowlist_file = File.open('./allowlist.txt')
    @allowlist = allowlist_file.readlines.map(&:chomp)
    archivelist_file = File.open('./archivelist.txt')
    @archivelist = archivelist_file.readlines.map(&:chomp)
    @subtypes = %w[channel_leave channel_join channel_topic channel_purpose]
    @retry_delay = ENV['RETRY_DELAY'].nil? ? ENV['RETRY_DELAY'] : 10
  end

  def slack_client
    Slack::Web::Client.new(token: ENV['BOT_TOKEN'])
  end

  def dry_run_message
    if @dry_run
      puts 'THIS IS A DRY RUN! No Channels will be archived'
    else
      puts 'THIS IS NOT A DRY RUN! Channels will be archived'
    end
  end

  def in_allowlist?(channel)
    allowlist.include?(channel.name)
  end

  def in_archivelist?(channel)
    archivelist.include?(channel.name)
  end

  def channel_info(channel)
    slack_client.conversations_info(channel: channel.id).channel
  end

  def channel_purpose(channel)
    channel_info(channel).purpose.value
  end

  def channel_topic(channel)
    channel_info(channel).topic.value
  end

  def days_since_last_active(channel)
    retries ||= 0
    slack_client.conversations_join(channel: channel.id) unless channel.is_member

    channel_history = slack_client.conversations_history(channel: channel.id, limit: 100).messages
    channel_history.reject! { |m| subtypes.include?(m.subtype) }
    channel_history.reject! { |m| m.bot_profile && m.bot_profile.name == 'auto-archive' }
    latest_message_ts = channel_history.empty? ? channel_info(channel).last_read : channel_history.first.ts
    [true, (DateTime.now.new_offset(0) - DateTime.strptime(latest_message_ts, '%s')).to_i]
  rescue Slack::Web::Api::Errors::SlackError => e
    sleep(retry_delay) if retry_delay
    retry if (retries += 1) < 2
    raise e.message
  end

  def skip_archival?(channel)
    return true if channel_topic(channel).downcase.include?('noarchive')
    return true if channel_purpose(channel).downcase.include?('noarchive')
    return true if in_allowlist?(channel)

    false
  end

  def check_channels(conversations_list)
    conversations_list.channels.each do |channel|
      next unless archivelist.empty? || (!archivelist.empty? && in_archivelist?(channel))

      active, days_active = days_since_last_active(channel)
      next if skip_archival?(channel)
      next if active && days_active < days_inactive

      archive_candidates[channel] = days_active
    rescue Slack::Web::Api::Errors::SlackError => e
      puts "Error while checking #{channel.name}: #{e.message}"
      next
    rescue Slack::Web::Api::Errors::TooManyRequestsError => e
      puts "Too Many Requests, sleeping for #{e.retry_after}"
      sleep(e.retry_after)
      retry
    rescue => e
      puts "Error while checking #{channel.name}: #{e.message}: #{e.class}"
      next
    end
    conversations_list.response_metadata.next_cursor
  end

  def find_channels_to_archive
    next_cursor = ''
    loop do
      options = { exclude_archived: true, limit: 1000, types: 'public_channel,private_channel', cursor: next_cursor }
      conversations_list = slack_client.conversations_list(options)
      next_cursor = check_channels(conversations_list)
      break if next_cursor.empty?
    end
    archive_candidates
  end

  def warned?(channel, warning_text)
    retries ||= 0
    slack_client.conversations_join(channel: channel.id) unless channel.is_member

    channel_history = slack_client.conversations_history(channel: channel.id, limit: 100).messages
    channel_history.any? { |m| m.bot_profile && m.text == warning_text } ? true : false
  rescue Slack::Web::Api::Errors::SlackError => e
    sleep(retry_delay) if retry_delay
    retry if (retries += 1) < 2
    raise e.message
  end

  def archival_warn_message(channel, days_since_last_active)
    text = "This channel has been inactive for #{days_since_last_active} days and will soon be archived."\
           " If you prefer to not archive this channel, please keep active or add a 'noarchive' "\
           'to the topic or profile of this channel.'
    warned = warned?(channel, text)
    puts "#{text}: Already Warned = #{warned}"
    return true if warned || !@dry_run

    response = slack_client.chat_postMessage(channel: channel.id, text: text)
    response.ok
  end

  def post_archival_message(channel, days_since_last_active)
    text = "This channel has been inactive for #{days_since_last_active} days and so is being archived."
    puts text
    response = slack_client.chat_postMessage(channel: channel.id, text: text)
    response.ok
  end

  def archive
    archive_candidates.each do |channel, days_since_last_active|
      puts "Archiving channel #{channel.name} now..."
      success = post_archival_message(channel, days_since_last_active)
      slack_client.conversations_archive(channel: channel.id) if success
    end
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: example.rb [options]'

  opts.on('-d <true/false>', '--dryrun <true/false>', 'Set Dry Run to true or false. Defaults to true') do |d|
    options[:dry_run] = d
  end
  opts.on('-h', '--help', 'Prints this help') do
    puts opts
    exit
  end
end.parse!

dry_run = options[:dry_run] || true
reaper = ChannelReaper.new(dry_run)
reaper.dry_run_message
archive_candidates = reaper.find_channels_to_archive
puts 'The following channels will be archived'
archive_candidates.each do |channel, days_since_last_active|
  puts "#{channel.name}: #{days_since_last_active} days since last active"
  # success = reaper.archival_warn_message(channel, days_since_last_active)
  # puts "Warned on #{channel.name}" if success
end
unless reaper.dry_run
  puts 'Archiving now...'
  reaper.archive
end
