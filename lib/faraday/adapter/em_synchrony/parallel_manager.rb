# frozen_string_literal: true

module Faraday
  class Adapter
    class EMSynchrony < Faraday::Adapter
      # A parallel manager for EMSynchrony.
      class ParallelManager
        # Add requests to queue.
        #
        # @param request [EM::HttpRequest]
        # @param method [Symbol, String] HTTP method
        # @param args [Array] the rest of the positional arguments
        def add(request, method, *args, &block)
          queue << {
            request: request,
            method: method,
            args: args,
            block: block
          }
        end

        # Run all requests on queue with `EM::Synchrony::Multi`, wrapping
        # it in a reactor and fiber if needed.
        def run
          result = nil
          if !EM.reactor_running?
            EM.run do
              Fiber.new do
                result = perform
                EM.stop
              end.resume
            end
          else
            result = perform
          end
          result
        end

        private

        # The request queue.
        def queue
          @queue ||= []
        end

        # Main `EM::Synchrony::Multi` performer.
        def perform
          multi = ::EM::Synchrony::Multi.new

          queue.each do |item|
            method = "a#{item[:method]}".to_sym

            req = item[:request].send(method, *item[:args])
            req.callback(&item[:block])

            req_name = "req_#{multi.requests.size}".to_sym
            multi.add(req_name, req)
          end

          # Clear the queue, so parallel manager objects can be reused.
          @queue = []

          # Block fiber until all requests have returned.
          multi.perform
        end
      end
    end
  end
end
