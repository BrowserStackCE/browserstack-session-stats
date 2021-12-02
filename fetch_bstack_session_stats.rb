# frozen_string_literal: true

require 'rubygems'
require 'rest-client'
require 'json'
require 'net/http'
require 'time'
require 'yaml'


class Command
  def initialize(curr_timestamp, command_type, full_command)
    @curr_timestamp = curr_timestamp
    @command_type = command_type
    @full_command = full_command
  end

  def get_command_type
    @command_type
  end

  def get_curr_timestamp
    @curr_timestamp
  end

  def get_full_command
    @full_command
  end
end

begin
  session_hash_data_to_analyse = {}
  analysis_mode = ARGV[0]
  build_or_session_id = ARGV[1]
  limit = 100
  offset = 0
  session_count_iterator = 1
  config_array = YAML.load(File.read("config.yml"))

  loop do
    if analysis_mode == 'build'
      base_url = "https://#{ENV['BROWSERSTACK_USERNAME']}:#{ENV['BROWSERSTACK_ACCESS_KEY']}@api.browserstack.com/automate/builds/#{build_or_session_id}/sessions.json?limit=#{limit}&offset=#{offset}"
    elsif analysis_mode == 'session'
      base_url = "https://#{ENV['BROWSERSTACK_USERNAME']}:#{ENV['BROWSERSTACK_ACCESS_KEY']}@api.browserstack.com/automate/sessions/#{build_or_session_id}.json"
    end

    results = RestClient.get(base_url)
    results_json = JSON.parse(results.body)

    if (analysis_mode == 'build' && !results_json.empty?) || ((analysis_mode == 'session' && session_count_iterator == 1))
      session_count_iterator += 1
      (0..results_json.length - 1).each do |i|
        if results_json.length > 1
          automation_session_raw_logs = results_json[i]['automation_session']['logs']
          automation_session_duration = results_json[i]['automation_session']['duration']
          session_id = results_json[i]['automation_session']['hashed_id']
          video_url = results_json[i]['automation_session']['video_url']
        else
          automation_session_raw_logs = results_json['automation_session']['logs']
          automation_session_duration = results_json['automation_session']['duration']
          session_id = results_json['automation_session']['hashed_id']
          video_url = results_json['automation_session']['video_url']
        end
        latency_data_to_analyse = []
        uri = URI(automation_session_raw_logs)

        req = Net::HTTP::Get.new(uri)
        req.basic_auth (ENV['BROWSERSTACK_USERNAME']).to_s, (ENV['BROWSERSTACK_ACCESS_KEY']).to_s

        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(req)
        end
        cmd_list = []
        res.body.lines.each do |line|
          line_split = line.split
          next if line_split.empty?
          ts_split = line_split[1].split(':')
          cmd = Command.new(Time.parse("#{line_split[0]} #{ts_split[0]}:#{ts_split[1]}:#{ts_split[2]}.#{ts_split[3]}"), (line_split[2]).to_s, line.to_s)
          cmd_list.push(cmd)
        end

        inside_time = 0.0
        outside_time = 0.0
        stop_session_time = 0.0
        tot_reqs = 0
        (0..cmd_list.length - 1).each do |i|
          if !cmd_list[i + 1].nil? && (cmd_list[i].get_command_type == 'REQUEST' && cmd_list[i + 1].get_command_type == 'RESPONSE') || (cmd_list[i].get_command_type == 'REQUEST' && ['DEBUG'].include?(cmd_list[i+1].get_command_type) && !cmd_list[i + 2].nil? && cmd_list[i + 2].get_command_type == 'RESPONSE')
            curr_resp_minus_req = (cmd_list[i + 1].get_curr_timestamp - cmd_list[i].get_curr_timestamp)
            inside_time += curr_resp_minus_req
            tot_reqs += 1
            if curr_resp_minus_req > config_array["config"]["inside_time_threshold"]
              latency_data_to_analyse.push "HIGH INSIDE TIME: #{curr_resp_minus_req} seconds.\nRESPONSE:#{cmd_list[i + 1].get_curr_timestamp} #{cmd_list[i + 1].get_command_type}\nREQUEST      :#{cmd_list[i].get_curr_timestamp} #{cmd_list[i].get_command_type}\nFULL COMMANDS:\nRESPONSE:#{cmd_list[i + 1].get_full_command}\nREQUEST:#{cmd_list[i].get_full_command}\n\n"
            end
          end
          if !cmd_list[i + 1].nil? && cmd_list[i].get_command_type == 'RESPONSE' && cmd_list[i + 1].get_command_type == 'REQUEST'
            curr_req_minus_prev_resp = (cmd_list[i + 1].get_curr_timestamp - cmd_list[i].get_curr_timestamp)
            outside_time += curr_req_minus_prev_resp
            if curr_req_minus_prev_resp > config_array["config"]["outside_time_threshold"]
              latency_data_to_analyse.push "HIGH OUTSIDE TIME: #{curr_req_minus_prev_resp} seconds.\nREQUEST      :#{cmd_list[i + 1].get_curr_timestamp} #{cmd_list[i + 1].get_command_type}\nPREV RESPONSE:#{cmd_list[i].get_curr_timestamp} #{cmd_list[i].get_command_type}\nFULL COMMANDS:\nREQUEST:#{cmd_list[i + 1].get_full_command}\nPREV RESPONSE:#{cmd_list[i].get_full_command}\n\n"
            end
          end
          next unless !cmd_list[i + 1].nil? && cmd_list[i].get_command_type == 'RESPONSE' && cmd_list[i + 1].get_command_type == 'STOP_SESSION'

          stop_session_time = (cmd_list[i + 1].get_curr_timestamp - cmd_list[i].get_curr_timestamp)
          if stop_session_time > config_array["config"]["session_stop_time_threshold"]
            latency_data_to_analyse.push "HIGH SESSION STOP TIME: #{stop_session_time} seconds.\nSESSION STOP:#{cmd_list[i + 1].get_curr_timestamp} #{cmd_list[i + 1].get_command_type}\nPREV RESPONSE:#{cmd_list[i].get_curr_timestamp} #{cmd_list[i].get_command_type}\nFULL COMMANDS:\nSESSION STOP:#{cmd_list[i + 1].get_full_command}\nPREV RESPONSE:#{cmd_list[i].get_full_command}\n\n"
          end
        end
        session_hash_data_to_analyse[session_id] = latency_data_to_analyse

        delta_unaccounted_time = automation_session_duration - inside_time - outside_time - stop_session_time
        inside_time_per = inside_time * 100 / automation_session_duration
        outside_time_per = outside_time * 100 / automation_session_duration
        delta_unaccounted_time_per = delta_unaccounted_time * 100 / automation_session_duration

        puts "\nSession_ID:\t\t\t#{session_id}\n\n"
        puts "Inside_Time:\t\t\t#{inside_time.round(3)} seconds"
        puts "Outside_Time:\t\t\t#{outside_time.round(3)} seconds"
        puts "Unaccounted_Time:\t\t#{delta_unaccounted_time.round(3)} seconds"
        puts "Total_Session_Time:\t\t#{automation_session_duration.round(3)} seconds\n\n"
        puts "Inside_Time_Percent:\t\t#{inside_time_per.round(3)}%"
        puts "Outside_Time_Percent:\t\t#{outside_time_per.round(3)}%"
        puts "Unaccounted_Time_Percentage:\t#{delta_unaccounted_time_per.round(3)}%\n\n"
        puts "Total_REQs:\t\t\t#{tot_reqs}"
        puts "STOP_SESSION_Time:\t\t#{stop_session_time}\n\n"
        
        if analysis_mode == 'session'
          puts "\nVideo URL: #{video_url}"
          puts "\nRaw Logs: #{automation_session_raw_logs}"
        end
      end
    else
      break
    end
    offset += limit
  end

  puts "\n\n"
  session_hash_data_to_analyse.each do |key, value|
    puts "Session id: #{key}\n"
    value.each do |entry|
      puts "Latency info entry: \n#{entry}\n"
    end
    puts "--------------------------------------------------\n\n"
  end
rescue StandardError => e
  puts "A runtime exception occurred while processing the request: #{e.message}"
  print "Exception trace:\n"
  puts e.backtrace
end
