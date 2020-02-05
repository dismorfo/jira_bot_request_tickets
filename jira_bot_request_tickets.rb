#!/usr/bin/env ruby

# frozen_string_literal: true

require 'rubygems'
require 'bundler/setup'
require 'dotenv/load'
require 'optimist'
require 'json'
require 'digest'
require 'http'
require 'mime/types'

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

def job_source_entity_available?(content_directory, job)
  source_entity_directory = "#{content_directory}/#{job[:partner]}/#{job[:collection]}/wip/se"
  return false unless Dir.exist?(source_entity_directory)

  true
end

def string_to_file(string, filename, type = MIME::Types.type_for('json').first.content_type)
  file = StringIO.new(string)

  file.instance_variable_set(:@path, filename)

  def file.path
    @path
  end

  file.instance_variable_set(:@type, type)
  def file.content_type
    @type
  end

  file
end

def request_tickets(configuration)
  tickets = []
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
      reporter: details['fields']['reporter']['key'],
      project: details['fields']['project']['key'],
      resources: [],
      attachments: [],
      errors: []
    }
    details['fields']['attachment'].each do |attachment|
      next unless attachment['filename'] == 'job.txt'

      content = HTTP.basic_auth(configuration[:challenge]).get(attachment['content'])
      content.to_s.each_line do |line|
        next if line.strip.empty?

        job = infer_job_from_string(line)
        ticket[:errors].push(line) unless job.empty? || job_source_entity_available?(configuration[:content_directory], job)

        ticket[:resources].push(job) if job_source_entity_available?(configuration[:content_directory], job)
      end
    end

    tickets.push(ticket)
  end

  tickets.each do |ticket|
    # Example of adding a comment to the ticket
    if ticket[:errors].length.positive?
      puts 'error found'
      # # Add a comment
      # comment_url = "#{configuration[:jira_endpoint]}/rest/api/2/issue/#{ticket[:id]}/comment"
      # request = HTTP.basic_auth(configuration[:challenge]).post(
      #   comment_url,
      #   json: {
      #     body: "[~#{ticket[:reporter]}] Please note, error found with the following resources: #{ticket[:errors].join(', ')}"
      #   }
      # )
      # # @TODO: Check the response to see if the post was successful
      # # Assign issue to reporter
      # assign_url = "#{configuration[:jira_endpoint]}/rest/api/2/issue/#{ticket[:id]}"
      # HTTP.basic_auth(configuration[:challenge]).put(
      #   assign_url,
      #   json: {
      #     fields: {
      #       assignee: {
      #         name: ticket[:reporter]
      #       }
      #     }
      #   }
      # )
      # @TODO: Check the response to see if the post was successful
      next
    end
    # https://docs.atlassian.com/software/jira/docs/api/REST/8.7.0/#api/2/issue/{issueIdOrKey}/attachments-addAttachment
    # api/2/issue/{issueIdOrKey}/attachments
    attachment_url = "#{configuration[:jira_endpoint]}/rest/api/2/issue/#{ticket[:id]}/attachments"
    puts string_to_file(ticket[:resources].to_json, 'resources.json')
    HTTP
      .headers('X-Atlassian-Token': 'no-check')
      .basic_auth(configuration[:challenge]).post(
        attachment_url,
        form: {
          file: HTTP::FormData::File.new(string_to_file(ticket[:resources].to_json, 'resources.json'))
        }
      )
  end

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
request_tickets(
  content_directory: ENV['ROOT_CONTENT_DIRECTORY'],
  tickets_directory: ENV['TICKETS_DIRECTORY'],
  jira_endpoint: ENV['JIRA_ENDPOINT'],
  challenge: {
    user: ENV['HTTP_CHALLENGE_USER'],
    pass: ENV['HTTP_CHALLENGE_PASS']
  }
)

# puts infer_job_from_string('tamwag') # nil
# puts infer_job_from_string('tamwag/rosie')
# puts infer_job_from_string('tamwag/rosie/2_ESTHER_HORNE')
# puts infer_job_from_string('tamwag/rosie/2_ESTHER_HORNE/2_ESTHER_HORNE') # nil
# puts job_source_entity_available?(ENV['ROOT_CONTENT_DIRECTORY'], infer_job_from_string('tamwag/rosie'))

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

# rubocop:enable Metrics/BlockLength
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/AbcSize
# rubocop:enable Layout/LineLength
