[![Build Status](https://secure.travis-ci.org/mrkamel/swift_client.png?branch=master)](http://travis-ci.org/mrkamel/swift_client)
[![Code Climate](https://codeclimate.com/github/mrkamel/swift_client.png)](https://codeclimate.com/github/mrkamel/swift_client)
[![Dependency Status](https://gemnasium.com/mrkamel/swift_client.png?travis)](https://gemnasium.com/mrkamel/swift_client)
[![Gem Version](https://badge.fury.io/rb/swift_client.svg)](http://badge.fury.io/rb/swift_client)

# SwiftClient

Small but powerful client to interact with OpenStack Swift.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'swift_client'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install swift_client

## Usage

First, connect to a Swift cluster:

```ruby
swift_client = SwiftClient.new(
  :auth_url => "https://example.com/auth/v1.0",
  :username => "account:username",
  :api_key => "api key",
  :temp_url_key => "temp url key",
  :storage_url => "https://example.com/v1/AUTH_account"
)
```

To connect via v2 you have to add version and method specific details:

```ruby
swift_client = SwiftClient.new(
  :auth_url => "https://auth.example.com/v2.0",
  :storage_url => "https://storage.example.com/v1/AUTH_account",
  :tenant_name => "tenant",
  :username => "username",
  :password => "password"
)

# OR

swift_client = SwiftClient.new(
  :auth_url => "https://auth.example.com/v2.0",
  :storage_url => "https://storage.example.com/v1/AUTH_account",
  :tenant_name => "tenant",
  :access_key => "access key",
  :secret_key => "secret key"
)
```

To connect via v3:

```ruby
swift_client = SwiftClient.new(
  :auth_url => "https://auth.example.com/v3",
  :storage_url => "https://storage.example.com/v1/AUTH_account",
  :username => "username",
  :password => "password",
  :user_domain => "example.com" # :user_domain_id => "..." is valid as well
)

# OR

# project scoped authentication

swift_client = SwiftClient.new(
  :auth_url => "https://auth.example.com/v3",
  :username => "username",
  :password => "password",
  :user_domain => "example.com", # :user_domain_id => "..." is valid as well
  :project_id => "p-123456", # :project_name => "..." is valid as well
  :project_domain_id => "d-123456" # :project_domain_name => "..." is valid as well
)

# OR

# domain scoped authentication

swift_client = SwiftClient.new(
  :auth_url => "https://auth.example.com/v3",
  :username => "username",
  :password => "password",
  :user_domain => "example.com", # :user_domain_id => "..." is valid as well
  :domain_id => "d-123456" # :domain_name => "..." is valid as well
)

# OR

swift_client = SwiftClient.new(
  :auth_url => "https://auth.example.com/v3",
  :storage_url => "https://storage.example.com/v1/AUTH_account",
  :user_id => "user id",
  :password => "password",
  :interface => "internal"
)

# OR

swift_client = SwiftClient.new(
  :auth_url => "https://auth.example.com/v3",
  :storage_url => "https://storage.example.com/v1/AUTH_account",
  :token => "token"
)
```

where `temp_url_key` and `storage_url` are optional.

SwiftClient will automatically reconnect in case the endpoint responds with 401
Unauthorized to one of your requests using the provided credentials. In case
the endpoint does not respond with 2xx to any of SwiftClient's requests,
SwiftClient will raise a `SwiftClient::ResponseError`. Otherwise, SwiftClient
responds with an `HTTParty::Response` object, such that you can call `#headers`
to access the response headers or `#body` as well as `#parsed_response` to
access the response body and JSON response. Checkout the
[HTTParty](https://github.com/jnunemaker/httparty) gem to learn more.

SwiftClient offers the following requests:

* `head_account(options = {}) # => HTTParty::Response`
* `post_account(headers = {}, options = {}) # => HTTParty::Response`
* `head_containers(options = {}) # => HTTParty::Response`
* `get_containers(query = {}, options = {}) # => HTTParty::Response`
* `paginate_containers(query = {}, options = {}) # => Enumerator`
* `get_container(container_name, query = {}, options = {}) # => HTTParty::Response`
* `paginate_container(container_name, query = {}, options = {}) # => Enumerator`
* `head_container(container_name, options = {}) # => HTTParty::Response`
* `put_container(container_name, headers = {}, options = {}) # => HTTParty::Response`
* `post_container(container_name, headers = {}, options = {}) # => HTTParty::Response`
* `delete_container(container_name, options = {}) # => HTTParty::Response`
* `put_object(object_name, data_or_io, container_name, headers = {}, options = {}) # => HTTParty::Response`
* `post_object(object_name, container_name, headers = {}, options = {}) # => HTTParty::Response`
* `get_object(object_name, container_name, options = {}) -> HTTParty::Response`
* `get_object(object_name, container_name, options = {}) { |chunk| save chunk } # => HTTParty::Response`
* `head_object(object_name, container_name, options = {}) # => HTTParty::Response`
* `delete_object(object_name, container_name, options = {}) # => HTTParty::Response`
* `get_objects(container_name, query = {}, options = {}) # => HTTParty::Response`
* `paginate_objects(container_name, query = {}, options = {}) # => Enumerator`
* `public_url(object_name, container_name) # => HTTParty::Response`
* `temp_url(object_name, container_name, options = {}) # => HTTParty::Response`
* `bulk_delete(entries, options = {}) # => entries`
* `post_head(object_name, container_name, _headers = {}, options = {}) # => HTTParty::Response`

By default, the client instructs the Swift server to return JSON via an HTTP Accept header; to disable this pass `:json => false` in `options`. The rest of the `options` are passed directly to the internal [HTTParty](https://rubygems.org/gems/httparty) client.

### Getting large objects
The `get_object` method with out a block is suitable for small objects that easily fit in memory. For larger objects, specify a block to process chunked data as it comes in.

```ruby
File.open("/tmp/output", "wb") do |file_io|
  swift_client.get_object("/large/object", "container") do |chunk|
    file_io.write(chunk)
  end
end
```

## Re-Using/Sharing/Caching Auth Tokens

Certain OpenStack/Swift providers have limits in place regarding token
generation. To re-use auth tokens by caching them via memcached, install dalli

`gem install dalli`

and provide an instance of Dalli::Client to SwiftClient:

```ruby
swift_client = SwiftClient.new(
  :auth_url => "https://example.com/auth/v1.0",
  ...
  :cache_store => Dalli::Client.new
)
```

The cache key used to store the auth token will include all neccessary details
to ensure the auth token won't be used for a different swift account erroneously.

The cache implementation of SwiftClient is not restricted to memcached. To use
a different one, simply implement a driver for your favorite cache store. See
[null_cache.rb](https://github.com/mrkamel/swift_client/blob/master/lib/swift_client/null_cache.rb)
for more info.

## bulk_delete

Takes an array containing container_name/object_name entries.
Automatically slices and sends 1_000 items per request.

## Non-chunked uploads

By default files are uploaded in chunks and using a `Transfer-Encoding:
chunked` header. You can override this by passing a `Transfer-Encoding:
identity` header:

```ruby
put_object(object_name, data_or_io, container_name, "Transfer-Encoding" => "identity")
```

## Contributing

1. Fork it ( https://github.com/mrkamel/swift_client/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Semantic Versioning

Starting with version 0.2.0, SwiftClient uses Semantic Versioning:
[SemVer](http://semver.org/)
