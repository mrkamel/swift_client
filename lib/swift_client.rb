
require "swift_client/version"

require "httparty"
require "mime-types"
require "openssl"
require "stringio"

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

  def paginate_containers(query = {}, &block)
    paginate :get_containers, query, &block
  end

  def get_container(container_name, query = {})
    raise(EmptyNameError) if container_name.empty?

    request :get, "/#{container_name}", :query => query
  end

  def paginate_container(container_name, query = {}, &block)
    paginate :get_container, container_name, query, &block
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

    extended_headers = (headers || {}).dup

    unless find_header_key(extended_headers, "Content-Type")
      extended_headers["Content-Type"] = mime_type.content_type if mime_type
      extended_headers["Content-Type"] ||= "application/octet-stream"
    end

    extended_headers["Transfer-Encoding"] = "chunked"

    request :put, "/#{container_name}/#{object_name}", :body_stream => data_or_io.respond_to?(:read) ? data_or_io : StringIO.new(data_or_io), :headers => extended_headers
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

  def paginate_objects(container_name, query = {}, &block)
    paginate :get_objects, container_name, query, &block
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

  def find_header_key(headers, key)
    headers.keys.detect { |k| k.downcase == key.downcase }
  end

  def request(method, path, opts = {})
    headers = (opts[:headers] || {}).dup
    headers["X-Auth-Token"] = auth_token
    headers["Accept"] = "application/json"

    stream_pos = opts[:body_stream].pos if opts[:body_stream]

    response = HTTParty.send(method, "#{storage_url}#{path}", opts.merge(:headers => headers))

    if response.code == 401
      authenticate

      opts[:body_stream].pos = stream_pos if opts[:body_stream]

      return request(method, path, opts)
    end

    raise(ResponseError.new(response.code, response.message)) unless response.success?

    response
  end

  def authenticate
    return authenticate_v3 if options[:auth_url] =~ /v3/
    return authenticate_v2 if options[:auth_url] =~ /v2/

    authenticate_v1
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

  def authenticate_v3
    raise(AuthenticationError, "auth_url missing") unless options[:auth_url]
    raise(AuthenticationError, "username in combination with domain/domain_id is deprecated, please use user_domain/user_domain_id instead") if options[:username] && (options[:domain] || options[:domain_id]) && !options[:user_domain] && !options[:user_domain_id]

    auth = { "auth" => { "identity" => {} } }

    if options[:username] && options[:password] && (options[:user_domain] || options[:user_domain_id])
      auth["auth"]["identity"]["methods"] = ["password"]
      auth["auth"]["identity"]["password"] = { "user" => { "name" => options[:username], "password" => options[:password] } }
      auth["auth"]["identity"]["password"]["user"]["domain"] = options[:user_domain] ? { "name" => options[:user_domain] } : { "id" => options[:user_domain_id] }
    elsif options[:user_id] && options[:password]
      auth["auth"]["identity"]["methods"] = ["password"]
      auth["auth"]["identity"]["password"] = { "user" => { "id" => options[:user_id], "password" => options[:password] } }
    elsif options[:token]
      auth["auth"]["identity"]["methods"] = ["token"]
      auth["auth"]["identity"]["token"] = { "id" => options[:token] }
    else
      raise AuthenticationError, "Unknown authentication method"
    end

    # handle project authentication scope

    if (options[:project_id] || options[:project_name]) && (options[:project_domain_name] || options[:project_domain_id])
      auth["auth"]["scope"] = { "project" => { "domain" => {} } }
      auth["auth"]["scope"]["project"]["name"] =  options[:project_name] if options[:project_name]
      auth["auth"]["scope"]["project"]["id"] =  options[:project_id] if options[:project_id]
      auth["auth"]["scope"]["project"]["domain"]["name"] = options[:project_domain_name] if options[:project_domain_name]
      auth["auth"]["scope"]["project"]["domain"]["id"] = options[:project_domain_id] if options[:project_domain_id]
    end

    # handle domain authentication scope

    if options[:domain_name] || options[:domain_id]
      auth["auth"]["scope"] = { "domain" => {} }
      auth["auth"]["scope"]["domain"]["name"] = options[:domain_name] if options[:domain_name]
      auth["auth"]["scope"]["domain"]["id"] = options[:domain_id] if options[:domain_id]
    end

    response = HTTParty.post("#{options[:auth_url].gsub(/\/+$/, "")}/auth/tokens", :body => JSON.dump(auth), :headers => { "Content-Type" => "application/json" })

    raise(AuthenticationError, "#{response.code}: #{response.message}") unless response.success?

    self.auth_token = response.headers["X-Subject-Token"]
    self.storage_url = options[:storage_url] || storage_url_from_v3_response(response)

    raise(AuthenticationError, "storage_url missing") unless storage_url
  end

  def storage_url_from_v3_response(response)
    swift_services = Array(response.parsed_response["token"]["catalog"]).select { |service| service["type"] == "object-store" }
    swift_service = swift_services.first

    return unless swift_services.size == 1

    swift_endpoints = swift_service["endpoints"].select { |endpoint| endpoint["interface"] == "public" }
    swift_endpoint = swift_endpoints.first

    return unless swift_endpoints.size == 1

    swift_endpoint["url"]
  end

  def paginate(method, *args, query)
    return enum_for(:paginate, method, *args, query) unless block_given?

    marker = nil

    loop do
      response = send(method, *args, marker ? query.merge(:marker => marker) : query)

      return if response.parsed_response.empty?

      yield response

      marker = response.parsed_response.last["name"]
    end
  end
end

