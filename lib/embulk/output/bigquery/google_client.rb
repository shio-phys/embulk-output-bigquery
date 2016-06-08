require 'google/api_client/auth/key_utils'

module Embulk
  module Output
    class Bigquery < OutputPlugin
      class Error < StandardError; end
      class JobTimeoutError < Error; end
      class NotFoundError < Error; end
      class BackendError < Error; end

      class GoogleClient
        def initialize(task, scope, client_class)
          @task = task
          @scope = scope
          @client_class = client_class
        end

        def client
          return @cached_client if @cached_client && @cached_client_expiration > Time.now

          client = @client_class.new
          client.client_options.application_name = @task['application_name']
          client.request_options.retries = @task['retries']
          client.request_options.timeout_sec = @task['timeout_sec']
          client.request_options.open_timeout_sec = @task['open_timeout_sec']
          Embulk.logger.debug { "embulk-output-bigquery: client_options: #{client.client_options.to_h}" }
          Embulk.logger.debug { "embulk-output-bigquery: request_options: #{client.request_options.to_h}" }

          case @task['auth_method']
          when 'private_key'
            private_key_passphrase = 'notasecret'
            key = Google::APIClient::KeyUtils.load_from_pkcs12(@task['p12_keyfile'], private_key_passphrase)
            auth = Signet::OAuth2::Client.new(
              token_credential_uri: "https://accounts.google.com/o/oauth2/token",
              audience: "https://accounts.google.com/o/oauth2/token",
              scope: @scope,
              issuer: @task['service_account_email'],
              signing_key: key)

          when 'compute_engine'
            auth = Google::Auth::GCECredentials.new

          when 'json_key'
            json_key = @task['json_keyfile']
            if File.exist?(json_key)
              auth = File.open(json_key) do |f|
                Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: f, scope: @scope)
              end
            else
              key = StringIO.new(json_key)
              auth = Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: key, scope: @scope)
            end

          when 'application_default'
            auth = Google::Auth.get_application_default([@scope])

          else
            raise ConfigError, "Unknown auth method: #{@task['auth_method']}"
          end

          client.authorization = auth

          @cached_client_expiration = Time.now + 1800
          @cached_client = client
        end
      end
    end
  end
end
