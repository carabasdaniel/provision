#!/usr/bin/env ruby
require 'json'
require 'net/http'
require 'yaml'
require 'puppet_litmus'
require 'etc'
require_relative '../lib/task_helper'

def default_uri
  URI.parse('https://facade-main-6f3kfepqcq-ew.a.run.app/v1/provision')
end

def platform_to_cloud_request_parameters(platform)
  params = case platform
           when String
             { cloud: 'gcp', images: [platform] }
           when Array
             { cloud: 'gcp', images: platform }
           else
             platform[:cloud] = 'gcp' if platform[:cloud].nil?
             platform[:images] = [platform[:images]] if platform[:images].is_a?(String)
             platform
           end
  params
end

# curl -X POST -H "Authorization:bearer ${{ secrets.token }}" https://facade-validation-6f3kfepqcq-ew.a.run.app/v1/provision --data @test_machines.json
# Need a way to retrieve the token locally or from CI secrets? 🤔
# Explodes right now because we don't have a way to grab the GH url
def invoke_cloud_request(params, uri, job_url, token)
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "bearer #{token}"
  request.body = JSON.unparse(params.reject{|k| k == :uri})

  req_options = {
    use_ssl: uri.scheme == "https",
  }

  response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
    http.request(request)
  end
  File.write('inventory.yaml','wb') do |f|
    f.write(response.body)
  end
end

  # include PuppetLitmus::InventoryManipulation
def provision(platform, inventory_location, vars)
  #Call the provision service with the information necessary and write the inventory file locally
  job_url = ENV['GITHUB_URL']
  token = ENV['TOKEN']
  uri = ENV['SERVICE_URL']
  uri = default_uri if uri.nil?  
  if job_url.nil? || token.nil? 
    data = JSON.parse(vars.gsub(';',','))
    job_url = data['job_url']
    token = data['token']

  end
  params = platform_to_cloud_request_parameters(platform)
  invoke_cloud_request(params, uri, job_url, token)

  {status: 'ok', node_name: platform} 
end

def tear_down(platform, inventory_location, vars)
  #remove all provisioned resources
end

params = JSON.parse(STDIN.read)
platform = params['platform']
action = params['action']
vars = params['vars']
inventory_location = sanitise_inventory_location(params['inventory'])
raise 'specify a node_name when tearing down' if action == 'tear_down' && node_name.nil?
raise 'specify a platform when provisioning' if action == 'provision' && platform.nil?

begin
  result = provision(platform, inventory_location, vars) if action == 'provision'
  result = tear_down(node_name, inventory_location, vars) if action == 'tear_down'
  puts result.to_json
  exit 0
rescue => e
  puts({ _error: { kind: 'facter_task/failure', msg: e.message } }.to_json)
  exit 1
end
