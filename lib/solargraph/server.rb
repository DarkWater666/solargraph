require 'sinatra/base'
require 'thread'

module Solargraph
  class Server < Sinatra::Base
    set :port, 7657

    @@api_hash = {}
    @@semaphore = Mutex.new

    post '/prepare' do
      prepare_workspace params['directory']
    end

    post '/suggest' do
      content_type :json
      begin
        sugg = []
        workspace = params['workspace'] || CodeMap.find_workspace(params['filename'])
        Server.prepare_workspace workspace unless @@api_hash.has_key?(workspace)
        @@semaphore.synchronize {
          code_map = CodeMap.new(code: params['text'], filename: params['filename'], api_map: @@api_hash[workspace])
          offset = code_map.get_offset(params['line'].to_i, params['column'].to_i)
          sugg = code_map.suggest_at(offset, with_snippets: true, filtered: true)
        }
        { "status" => "ok", "suggestions" => sugg }.to_json
      rescue Exception => e
        STDERR.puts e
        STDERR.puts e.backtrace.join("\n")
        { "status" => "err", "message" => e.message + "\n" + e.backtrace.join("\n") }.to_json
      end
    end

    class << self
      def run!
        constant_updates
        super
      end

      def prepare_workspace directory
        api_map = Solargraph::ApiMap.new(directory)
        @@semaphore.synchronize {
          @@api_hash[directory] = api_map
        }
      end

      def constant_updates
        Thread.new {
          loop do
            @@api_hash.keys.each { |k|
              update = Solargraph::ApiMap.new(k)
              @@semaphore.synchronize {
                @@api_hash[k] = update
              }
            }
            sleep 2
          end
        }
      end
    end
  end
end
