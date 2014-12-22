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
swift_client = SwiftClient.new(:auth_url => "https://example.com/auth/v1.0", :username => "account:username", :api_key => "secret api key", :temp_url_key => "optional temp url key")
```

SwiftClient will automatically reconnect in case the endpoint responds with 401
Unauthorized to one of your requests using the provided credentials.
Otherwise, i.e. in case the endpoint does not respond with 2xx to any of
SwiftClient's requests, SwiftClient will raise a `SwiftClient::ResponseError`.

SwiftClient offers the following requests:

* head_account -> HTTParty::Response
* post_account(headers = {}) -> HTTParty::Response
* head_containers -> HTTParty::Response
* get_containers(query = {}) -> HTTParty::Response
* get_container(container, query = {}) -> HTTParty::Response
* head_container(container) -> HTTParty::Response
* put_container(container, headers = {}) -> HTTParty::Response
* post_container(container, headers = {}) -> HTTParty::Response
* delete_container(container) -> HTTParty::Response
* put_object(object, data_or_io, container, headers = {}) -> HTTParty::Response
* post_object(object, container, headers = {}) -> HTTParty::Response
* get_object(object, container) -> HTTParty::Response
* head_object(object, container) -> HTTParty::Response
* delete_object(object, container) -> HTTParty::Response
* get_objects(container, query = {}) -> HTTParty::Response
* public_url(object, container) -> HTTParty::Response
* temp_url(object, container) -> HTTParty::Response

## Contributing

1. Fork it ( https://github.com/mrkamel/swift_client/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
