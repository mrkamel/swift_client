
require "swift_client/version"
require "swift_client/null_cache"

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

  attr_accessor :options, :auth_token, :storage_url, :cache_store

  def initialize(options = {})
    raise(OptionError, "Setting expires_in connection wide is deprecated") if options[:expires_in]

    self.options = options
    self.cache_store = options[:cache_store] || SwiftClient::NullCache.new

    authenticate
  end

  def head_account(options = {})
    request :head, "/", options
  end

  def post_account(headers = {}, options = {})
    request :post, "/", options.merge(:headers => headers)
  end

  def head_containers(options = {})
    request :head, "/", options
  end

  def get_containers(query = {}, options = {})
    request :get, "/", options.merge(:query => query)
  end

  def paginate_containers(query = {}, options = {}, &block)
    paginate(:get_containers, query, options, &block)
  end

  def get_container(container_name, query = {}, options = {})
    raise(EmptyNameError) if container_name.empty?

    request :get, "/#{container_name}", options.merge(:query => query)
  end

  def paginate_container(container_name, query = {}, options = {}, &block)
    paginate(:get_container, container_name, query, options, &block)
  end

  def head_container(container_name, options = {})
    raise(EmptyNameError) if container_name.empty?

    request :head, "/#{container_name}", options
  end

  def put_container(container_name, headers = {}, options = {})
    raise(EmptyNameError) if container_name.empty?

    request :put, "/#{container_name}", options.merge(:headers => headers)
  end

  def post_container(container_name, headers = {}, options = {})
    raise(EmptyNameError) if container_name.empty?

    request :post, "/#{container_name}", options.merge(:headers => headers)
  end

  def delete_container(container_name, options = {})
    raise(EmptyNameError) if container_name.empty?

    request :delete, "/#{container_name}", options
  end

  def put_object(object_name, data_or_io, container_name, headers = {}, options = {})
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    mime_type = MIME::Types.of(object_name).first

    extended_headers = (headers || {}).dup

    unless find_header_key(extended_headers, "Content-Type")
      extended_headers["Content-Type"] = mime_type.content_type if mime_type
      extended_headers["Content-Type"] ||= "application/octet-stream"
    end

    extended_headers["Transfer-Encoding"] = "chunked"

    request :put, "/#{container_name}/#{object_name}", options.merge(:body_stream => data_or_io.respond_to?(:read) ? data_or_io : StringIO.new(data_or_io), :headers => extended_headers)
  end

  def post_object(object_name, container_name, headers = {}, options = {})
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    request :post, "/#{container_name}/#{object_name}", options.merge(:headers => headers)
  end

  def get_object(object_name, container_name, options = {}, &block)
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    request(:get, "/#{container_name}/#{object_name}", options.merge(block ? { :stream_body => true } : {}), &block)
  end

  def head_object(object_name, container_name, options = {})
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    request :head, "/#{container_name}/#{object_name}", options
  end

  def post_head(object_name, container_name, _headers = {}, options = {})
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    request :post, "/#{container_name}/#{object_name}", options.merge(headers: _headers)
  end

  def delete_object(object_name, container_name, options = {})
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    request :delete, "/#{container_name}/#{object_name}", options
  end

  def get_objects(container_name, query = {}, options = {})
    raise(EmptyNameError) if container_name.empty?

    request :get, "/#{container_name}", options.merge(:query => query)
  end

  def paginate_objects(container_name, query = {}, options = {}, &block)
    paginate(:get_objects, container_name, query, options, &block)
  end

  def public_url(object_name, container_name)
    raise(EmptyNameError) if object_name.empty? || container_name.empty?

    "#{storage_url}/#{container_name}/#{object_name}"
  end

  def temp_url(object_name, container_name, opts = {})
    raise(EmptyNameError) if object_name.empty? || container_name.empty?
    raise(TempUrlKeyMissing) unless options[:temp_url_key]

    expires = (Time.now + (opts[:expires_in] || 3600).to_i).to_i
    path = URI.parse("#{storage_url}/#{container_name}/#{object_name}").path

    signature = OpenSSL::HMAC.hexdigest("sha1", options[:temp_url_key], "GET\n#{expires}\n#{path}")

    "#{storage_url}/#{container_name}/#{object_name}?temp_url_sig=#{signature}&temp_url_expires=#{expires}"
  end

  def bulk_delete(items, options = {})
    items.each_slice(1_000) do |slice|
      request :delete, "/?bulk-delete", options.merge(:body => slice.join("\n"), :headers => { "Content-Type" => "text/plain" })
    end

    items
  end

  private

  def cache_key
    auth_keys = [:auth_url, :username, :access_key, :user_id, :user_domain, :user_domain_id, :domain_name,
      :domain_id, :token, :project_id, :project_name, :project_domain_name, :project_domain_id, :tenant_name]

    auth_key = auth_keys.collect { |key| options[key] }.inspect

    Digest::SHA1.hexdigest(auth_key)
  end

  def find_header_key(headers, key)
    headers.keys.detect { |k| k.downcase == key.downcase }
  end

  def request(method, path, opts = {}, &block)
    headers = (opts[:headers] || {}).dup
    headers["X-Auth-Token"] = auth_token
    headers["Accept"] = "application/json"

    stream_pos = opts[:body_stream].pos if opts[:body_stream]

    response = HTTParty.send(method, "#{storage_url}#{path}", opts.merge(:headers => headers), &block)

    if response.code == 401
      authenticate

      opts[:body_stream].pos = stream_pos if opts[:body_stream]

      return request(method, path, opts, &block)
    end

    raise(ResponseError.new(response.code, response.message)) unless response.success?

    response
  end

  def authenticate
    return if authenticate_from_cache

    return authenticate_v3 if options[:auth_url] =~ /v3/
    return authenticate_v2 if options[:auth_url] =~ /v2/

    authenticate_v1
  end

  def authenticate_from_cache
    cached_auth_token = cache_store.get("swift_client:auth_token:#{cache_key}")
    cached_storage_url = cache_store.get("swift_client:storage_url:#{cache_key}")

    return false if cached_auth_token.nil? || cached_storage_url.nil?

    if cached_auth_token != auth_token || cached_storage_url != storage_url
      self.auth_token = cached_auth_token
      self.storage_url = cached_storage_url

      return true
    end

    false
  end

  def set_authentication_details(auth_token, storage_url)
    cache_store.set("swift_client:auth_token:#{cache_key}", auth_token)
    cache_store.set("swift_client:storage_url:#{cache_key}", storage_url)

    self.auth_token = auth_token
    self.storage_url = storage_url
  end

  def authenticate_v1
    [:auth_url, :username, :api_key].each do |key|
      raise(AuthenticationError, "#{key} missing") unless options[key]
    end

    response = HTTParty.get(options[:auth_url], :headers => { "X-Auth-User" => options[:username], "X-Auth-Key" => options[:api_key] })

    raise(AuthenticationError, "#{response.code}: #{response.message}") unless response.success?

    set_authentication_details response.headers["X-Auth-Token"], options[:storage_url] || response.headers["X-Storage-Url"]
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

    set_authentication_details response.parsed_response["access"]["token"]["id"], options[:storage_url]
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

    storage_url = options[:storage_url] || storage_url_from_v3_response(response)

    raise(AuthenticationError, "storage_url missing") unless storage_url

    set_authentication_details response.headers["X-Subject-Token"], storage_url
  end

  def storage_url_from_v3_response(response)
    swift_services = Array(response.parsed_response["token"]["catalog"]).select { |service| service["type"] == "object-store" }
    swift_service = swift_services.first

    return unless swift_services.size == 1

    interface = options[:interface] || "public"
    swift_endpoints = swift_service["endpoints"].select { |endpoint| endpoint["interface"] == interface }
    swift_endpoint = swift_endpoints.first

    return unless swift_endpoints.size == 1

    swift_endpoint["url"]
  end

  def paginate(method, *args, query, options)
    return enum_for(:paginate, method, *args, query, options) unless block_given?

    marker = nil

    loop do
      response = send(method, *args, marker ? query.merge(:marker => marker) : query, options)

      return if response.parsed_response.empty?

      yield response

      marker = response.parsed_response.last["name"]
    end
  end
end
