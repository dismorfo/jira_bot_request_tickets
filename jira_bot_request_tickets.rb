#!/usr/bin/env ruby

# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'
require 'dotenv/load'
require 'optimist'
require 'json'
require 'digest'
require 'http'

# rubocop:disable Metrics/BlockLength
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/AbcSize
# rubocop:disable Layout/LineLength

# load environment variables
# first value set for a variable will win.
Dotenv.load(
  '.env.production',
  '.env.stage',
  '.env.development',
  '.env.local',
  '.env'
)

# raise an error if a configuration key is missing
Dotenv.require_keys('HTTP_CHALLENGE_USER')
Dotenv.require_keys('HTTP_CHALLENGE_PASS')
Dotenv.require_keys('ROOT_CONTENT_DIRECTORY')
Dotenv.require_keys('JIRA_ENDPOINT')

def infer_job_from_string(data)
  # I want to sanitize "data", not sure if I should use https://github.com/rgrove/sanitize
  # split data into  Array
  job = data.strip.split('/')
  # Size should be between 1 or 2
  return nil unless [2, 3].include?(job.size)
  # string does not include job
  return { partner: job[0], collection: job[1] } if [2].include?(job.size)
  # string includes job
  return { partner: job[0], collection: job[1], job: job[2] } if [3].include?(job.size)
end

def job_available?(job)
  puts job
end

def request_tickets(configuration)
  ticket = {}
  issues_url = "#{configuration[:jira_endpoint]}/rest/api/2/search?jql=assignee=currentuser()"
  request = JSON.parse(
    HTTP.basic_auth(configuration[:challenge]).get(issues_url)
  )
  request['issues'].each do |issue|
    details = JSON.parse(
      HTTP.basic_auth(configuration[:challenge]).get(issue['self'])
    )
    ticket = {
      id: details['key'],
      self: details['self'],
      project: details['fields']['project']['key'],
      resources: [],
      attachments: [],
      errors: []
    }
    details['fields']['attachment'].each do |attachment|
      ticket[:attachments].push(attachment['content']) unless attachment['filename'] == 'job.txt'

      content = HTTP.basic_auth(configuration[:challenge]).get(attachment['content'])
      content.to_s.each_line do |line|
        next if line.strip.empty?

        job = infer_job_from_string(line.strip.split('/'))
        ticket[:error].push(line) unless job.empty?

        ticket[:resources].push(
          partner: partner,
          collection: collection,
          job: job
        )
      end
    end

    puts JSON.pretty_generate(ticket)
  end

  # https://docs.atlassian.com/software/jira/docs/api/REST/8.7.0/#api/2/issue-getIssue
  #
  # Get issue
  # GET /rest/api/2/issue/{issueIdOrKey}
  # Archive issue
  # PUT /rest/api/2/issue/{issueIdOrKey}/assignee
  # Add comment
  # POST /rest/api/2/issue/{issueIdOrKey}/comment
  #
  # Get attachment
  # GET /rest/api/2/attachment/{id}

  # issues = "https://jira.nyu.edu/rest/api/2/search?jql=assignee=currentuser()"
end

# Application message to display as banner in
# the help menu.
banner = <<~BANNER

  Usage: jira_bot_request_tickets.rb

BANNER

Optimist.options do
  version 'jira_bot_request_tickets 0.0.1'
  banner banner
end

# commented out will I test def "infer_job_from_string"
# Init the run. We need to pass a configuration object with:
# request_tickets(
#   content_directory: ENV['ROOT_CONTENT_DIRECTORY'],
#   tickets_directory: ENV['TICKETS_DIRECTORY'],
#   jira_endpoint: ENV['JIRA_ENDPOINT'],
#   challenge: {
#     user: ENV['HTTP_CHALLENGE_USER'],
#     pass: ENV['HTTP_CHALLENGE_PASS']
#   }
# )

puts infer_job_from_string('tamwag') # nil
puts infer_job_from_string('tamwag/rosie')
puts infer_job_from_string('tamwag/rosie/2_ESTHER_HORNE')
puts infer_job_from_string('tamwag/rosie/2_ESTHER_HORNE/2_ESTHER_HORNE') # nil

# rubocop:enable Metrics/BlockLength
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/AbcSize
# rubocop:enable Layout/LineLength
