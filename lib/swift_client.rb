
require "swift_client/version"

require "httparty"
require "stringio"
require "mime-types"

class SwiftClient
  class AuthenticationError < StandardError; end
  class ResponseError < StandardError; end
  class OptionError < StandardError; end
  class EmptyNameError < StandardError; end
  class TempUrlMissing < StandardError; end

  attr_accessor :options, :auth_token, :storage_url

  def initialize(options = {})
    [:auth_url, :username, :api_key].each do |key|
      raise(OptionError, "#{key} is missing") unless options.key?(key)
    end

    self.options = options

    authenticate
  end

  def get_containers(query = {})
    request :get, "/", :query => query
  end

  def get_container(name, query = {})
    raise(EmptyNameError) if name.empty?

    request :get, "/#{name}", :query => query
  end

  def head_container(name)
    raise(EmptyNameError) if name.empty?

    request :head, "/#{name}"
  end

  def put_container(name, headers = {})
    raise(EmptyNameError) if name.empty?

    request :put, "/#{name}", :headers => headers
  end

  def post_container(name, headers = {})
    raise(EmptyNameError) if name.empty?

    request :post, "/#{name}", :headers => headers
  end

  def delete_container(name)
    raise(EmptyNameError) if name.empty?

    request :delete, "/#{name}"
  end

  def put_object(name, data_or_io, container, headers = {})
    raise(EmptyNameError) if name.empty? || container.empty?

    mime_type = MIME::Types.of(name).first

    extended_headers = headers.dup
    extended_headers["Content-Type"] ||= mime_type.content_type if mime_type

    request :put, "/#{container}/#{name}", :body => data_or_io.respond_to?(:read) ? data_or_io.read : data_or_io, :headers => extended_headers
  end

  def post_object(name, container, headers = {})
    raise(EmptyNameError) if name.empty? || container.empty?

    request :post, "/#{container}/#{name}", :headers => headers
  end

  def get_object(name, container)
    raise(EmptyNameError) if name.empty? || container.empty?

    request :get, "/#{container}/#{name}"
  end

  def head_object(name, container)
    raise(EmptyNameError) if name.empty? || container.empty?

    request :head, "/#{container}/#{name}"
  end

  def delete_object(name, container)
    raise(EmptyNameError) if name.empty? || container.empty?

    request :delete, "/#{container}/#{name}"
  end

  def get_objects(container, query = {})
    raise(EmptyNameError) if container.empty?

    request :get, "/#{container}", :query => query
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

    raise(ResponseError, "#{response.code}: #{response.message}") unless response.success?

    response
  end

  def authenticate
    response = HTTParty.get(options[:auth_url], :headers => { "X-Auth-User" => options[:username], "X-Auth-Key" => options[:api_key] })

    raise(AuthenticationError, "#{response.code}: #{response.message}") unless response.success?

    self.auth_token = response.headers["X-Auth-Token"]
    self.storage_url = response.headers["X-Storage-Url"]

    storage_url.gsub!(/^http:/, "https:") if options[:auth_url] =~ /^https:/
  end
end

