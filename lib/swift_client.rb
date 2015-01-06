
require "swift_client/version"

require "httparty"
require "mime-types"
require "openssl"

class SwiftClient
  class AuthenticationError < StandardError; end
  class OptionError < StandardError; end
  class EmptyNameError < StandardError; end
  class TempUrlKeyMissing < StandardError; end

  class ResponseError < StandardError
    attr_accessor :code, :message

    def initialize(code, message)
      self.code = code
      self.message = message
    end

    def to_s
      "#{code} #{message}"
    end
  end

  attr_accessor :options, :auth_token, :storage_url

  def initialize(options = {})
    self.options = options

    authenticate
  end

  def head_account
    request :head, "/"
  end

  def post_account(headers = {})
    request :post, "/", :headers => headers
  end

  def head_containers
    request :head, "/"
  end

  def get_containers(query = {})
    request :get, "/", :query => query
  end

  def get_container(container_name, query = {})
    raise(EmptyNameError) if container_name.empty?

    request :get, "/#{container_name}", :query => query
  end

  def head_container(container_name)
    raise(EmptyNameError) if container_name.empty?

    request :head, "/#{container_name}"
  end

  def put_container(container_name, headers = {})
    raise(EmptyNameError) if container_name.empty?

    request :put, "/#{container_name}", :headers => headers
  end

  def post_container(container_name, headers = {})
    raise(EmptyNameError) if container_name.empty?

    request :post, "/#{container_name}", :headers => headers
  end

  def delete_container(container_name)
    raise(EmptyNameError) if container_name.empty?

    request :delete, "/#{container_name}"
  end

  def put_object(object_name, data_or_io, container_name, headers = {})
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    mime_type = MIME::Types.of(object_name).first

    extended_headers = headers.dup
    extended_headers["Content-Type"] ||= mime_type.content_type if mime_type

    request :put, "/#{container_name}/#{object_name}", :body => data_or_io.respond_to?(:read) ? data_or_io.read : data_or_io, :headers => extended_headers
  end

  def post_object(object_name, container_name, headers = {})
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    request :post, "/#{container_name}/#{object_name}", :headers => headers
  end

  def get_object(object_name, container_name)
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    request :get, "/#{container_name}/#{object_name}"
  end

  def head_object(object_name, container_name)
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    request :head, "/#{container_name}/#{object_name}"
  end

  def delete_object(object_name, container_name)
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    request :delete, "/#{container_name}/#{object_name}"
  end

  def get_objects(container_name, query = {})
    raise(EmptyNameError) if container_name.empty?

    request :get, "/#{container_name}", :query => query
  end

  def public_url(object_name, container_name)
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    "#{storage_url}/#{container_name}/#{object_name}"
  end

  def temp_url(object_name, container_name, opts = {})
    raise(EmptyNameError) if object_name.empty? || container_name.empty?
    raise(TempUrlKeyMissing) unless options[:temp_url_key]

    expires = (Time.now + (options[:expires_in] || 3600).to_i).to_i
    path = URI.parse("#{storage_url}/#{container_name}/#{object_name}").path

    signature = OpenSSL::HMAC.hexdigest("sha1", options[:temp_url_key], "GET\n#{expires}\n#{path}")

    "#{storage_url}/#{container_name}/#{object_name}?temp_url_sig=#{signature}&temp_url_expires=#{expires}"
  end

  private

  def request(method, path, opts = {})
    opts[:headers] ||= {}
    opts[:headers]["X-Auth-Token"] = auth_token
    opts[:headers]["Accept"] = "application/json"

    response = HTTParty.send(method, "#{storage_url}#{path}", opts)

    if response.code == 401
      authenticate

      return request(method, path, opts)
    end

    raise(ResponseError.new(response.code, response.message)) unless response.success?

    response
  end

  def authenticate
    options[:auth_url] =~ /v2/ ? authenticate_v2 : authenticate_v1
  end

  def authenticate_v1
    [:auth_url, :username, :api_key].each do |key|
      raise(AuthenticationError, "#{key} missing") unless options[key]
    end

    response = HTTParty.get(options[:auth_url], :headers => { "X-Auth-User" => options[:username], "X-Auth-Key" => options[:api_key] })

    raise(AuthenticationError, "#{response.code}: #{response.message}") unless response.success?

    self.auth_token = response.headers["X-Auth-Token"]
    self.storage_url = options[:storage_url] || response.headers["X-Storage-Url"]
  end

  def authenticate_v2
    [:auth_url, :storage_url].each do |key|
      raise(AuthenticationError, "#{key} missing") unless options[key]
    end

    auth = { "auth" => {} }

    if options[:tenant_name]
      auth["auth"]["tenantName"] = options[:tenant_name]
    else
      raise AuthenticationError, "No tenant specified"
    end

    if options[:username] && options[:password]
      auth["auth"]["passwordCredentials"] = { "username" => options[:username], "password" => options[:password] }
    elsif options[:access_key] && options[:secret_key]
      auth["auth"]["apiAccessKeyCredentials"] = { "accessKey" => options[:access_key], "secretKey" => options[:secret_key] }
    else
      raise AuthenticationError, "Unknown authentication method"
    end

    response = HTTParty.post("#{options[:auth_url].gsub(/\/+$/, "")}/tokens", :body => JSON.dump(auth), :headers => { "Content-Type" => "application/json" })

    raise(AuthenticationError, "#{response.code}: #{response.message}") unless response.success?

    self.auth_token = response.parsed_response["access"]["token"]["id"]
    self.storage_url = options[:storage_url]
  end
end

