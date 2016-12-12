require 'test_helper'

class AwesomeSauceTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = AwesomeSauceGateway.new(login: 'login', password: 'password')
    @credit_card = credit_card
    @expired_card = credit_card('4000100011112224', {:year => '1999'})
    @amount = 100

    @options = {
      order_id: '1',
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_auth_or_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal '40292#sale', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_auth_or_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:incorrect_number], response.error_code
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_auth_or_purchase_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response

    assert_equal '40292#authonly', response.authorization
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_auth_or_purchase_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:incorrect_number], response.error_code
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)

    capture = @gateway.capture(@amount, '2214269051#authonly', @options)
    assert_success capture
    assert_equal '43622#capture', capture.authorization
    assert_equal nil, capture.error_code
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_capture_response)

    assert capture = @gateway.capture(@amount, '2214269051#authonly')
    assert_failure capture
    assert_equal Gateway::STANDARD_ERROR_CODE[:processing_error], capture.error_code
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_refund_or_void_response)

    assert refund = @gateway.refund(36.40, '2214269051#XXXX1234')
    assert_success refund
    assert_equal 'refund succeeded', refund.message
    assert_equal '43624#refund', refund.authorization
  end

  def test_failed_refund
    @gateway.expects(:ssl_post).returns(failed_refund_or_void_response)

    refund = @gateway.refund(nil, '')
    assert_failure refund
    assert_equal 'refund failed', refund.message
    assert_equal Gateway::STANDARD_ERROR_CODE[:processing_error], refund.error_code
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_refund_or_void_response)

    assert void = @gateway.void('')
    assert_success void
    assert_equal 'void succeeded', void.message
    assert_equal '43624#void', void.authorization
  end

  def test_failed_void
    @gateway.expects(:ssl_post).returns(failed_refund_or_void_response)

    void = @gateway.void('')
    assert_failure void
    assert_equal 'void failed', void.message
    assert_equal Gateway::STANDARD_ERROR_CODE[:processing_error], void.error_code
  end

  def test_successful_verify
    response = stub_comms do
      @gateway.verify(@credit_card)
    end.respond_with(successful_auth_or_purchase_response, successful_refund_or_void_response)
    assert_success response
  end

  def test_successful_verify_with_failed_void
    response = stub_comms do
      @gateway.verify(@credit_card, @options)
    end.respond_with(successful_auth_or_purchase_response, failed_refund_or_void_response)
    assert_success response
    assert_equal 'authonly succeeded', response.message
  end

  def test_failed_verify
    response = stub_comms do
      @gateway.verify(@credit_card, @options)
    end.respond_with(failed_auth_or_purchase_response, successful_refund_or_void_response)
    assert_failure response
    assert_not_nil response.message
  end

  def test_scrub
    assert @gateway.supports_scrubbing?
    assert_equal @gateway.scrub(pre_scrubbed), post_scrubbed
  end

  def test_bad_ref_id
    @gateway.expects(:ssl_post).returns(successful_auth_or_purchase_response)
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    @gateway.expects(:ssl_post).returns(successful_auth_or_purchase_response)
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    @gateway.expects(:ssl_post).returns(failed_refund_because_of_bogus_ref_id)
    refund = @gateway.refund(@amount, auth.authorization)
    assert_failure refund
    assert_equal "Bad ref id", refund.message
  end

  def test_failed_purchase_expired_card
    @gateway.expects(:ssl_post).returns(failed_purchase_because_of_expired_card)

    response = @gateway.purchase(@amount, @expired_card, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:expired_card], response.error_code
  end

  def test_failed_purchase_pickup_card
    @gateway.expects(:ssl_post).returns(failed_purchase_because_of_pickup_card)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:pickup_card], response.error_code
  end

  private

  def pre_scrubbed
    %q(
opening connection to sandbox.asgateway.com:80...
opened
<- "POST /api/auth HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nConnection: close\r\nHost: sandbox.asgateway.com\r\nContent-Length: 374\r\n\r\n"
<- "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<request>\n<action>purch</action>\n<merchant>spreedly@robertevans.org-api</merchant>\n<secret>fd6f66c679cd370d1e38002941948ea712c34b31717cba5160e05f2e0d91682601395ad6810d8605</secret>\n<amount>1.00</amount>\n<currency>USD</currency>\n<number>4000100011112224</number>\n<cv2>123</cv2>\n<exp>092017</exp>\n<name>Longbob Longsen</name>\n</request>\n"
-> "HTTP/1.1 200 OK \r\n"
-> "Connection: close\r\n"
-> "Content-Type: text/html;charset=utf-8\r\n"
-> "Content-Length: 131\r\n"
-> "X-Xss-Protection: 1; mode=block\r\n"
-> "X-Content-Type-Options: nosniff\r\n"
-> "X-Frame-Options: SAMEORIGIN\r\n"
-> "Server: WEBrick/1.3.1 (Ruby/2.2.1/2015-02-26)\r\n"
-> "Date: Mon, 12 Dec 2016 20:12:57 GMT\r\n"
-> "Set-Cookie: rack.session=BAh7CEkiD3Nlc3Npb25faWQGOgZFVEkiRTIyYjlmNDhjMzRjYzlhMzNmYmI2%0AYWQ4OGJiNDE4YzFmN2M1YjkzYzQ0OTBhMTk4ZWVmNzg2YjQwNjJlODA3NjMG%0AOwBGSSIJY3NyZgY7AEZJIiU0Y2RkMWQ1ZGIyMjAzZWE5NjBlOGM2NzVlMjc2%0AZGMyOQY7AEZJIg10cmFja2luZwY7AEZ7B0kiFEhUVFBfVVNFUl9BR0VOVAY7%0AAFRJIi0xOGU0MGUxNDAxZWVmNjdlMWFlNjllZmFiMDlhZmI3MWY4N2ZmYjgx%0ABjsARkkiGUhUVFBfQUNDRVBUX0xBTkdVQUdFBjsAVEkiLWRhMzlhM2VlNWU2%0AYjRiMGQzMjU1YmZlZjk1NjAxODkwYWZkODA3MDkGOwBG%0A--15e3b749c97976c0f6c06b224d29434bdbe24275; path=/; HttpOnly\r\n"
-> "Via: 1.1 vegur\r\n"
-> "\r\n"
reading 131 bytes...
-> "<response><merchant>spreedly@robertevans.org-api</merchant><success>true</success><code></code><err></err><id>43638</id></response>"
read 131 bytes
Conn close
    )

  end

  def post_scrubbed
     %q(
opening connection to sandbox.asgateway.com:80...
opened
<- "POST /api/auth HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nConnection: close\r\nHost: sandbox.asgateway.com\r\nContent-Length: 374\r\n\r\n"
<- "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<request>\n<action>purch</action>\n<merchant>spreedly@robertevans.org-api</merchant>\n<secret>[FILTERED]</secret>\n<amount>1.00</amount>\n<currency>USD</currency>\n<number>[FILTERED]</number>\n<cv2>[FILTERED]</cv2>\n<exp>092017</exp>\n<name>Longbob Longsen</name>\n</request>\n"
-> "HTTP/1.1 200 OK \r\n"
-> "Connection: close\r\n"
-> "Content-Type: text/html;charset=utf-8\r\n"
-> "Content-Length: 131\r\n"
-> "X-Xss-Protection: 1; mode=block\r\n"
-> "X-Content-Type-Options: nosniff\r\n"
-> "X-Frame-Options: SAMEORIGIN\r\n"
-> "Server: WEBrick/1.3.1 (Ruby/2.2.1/2015-02-26)\r\n"
-> "Date: Mon, 12 Dec 2016 20:12:57 GMT\r\n"
-> "Set-Cookie: rack.session=BAh7CEkiD3Nlc3Npb25faWQGOgZFVEkiRTIyYjlmNDhjMzRjYzlhMzNmYmI2%0AYWQ4OGJiNDE4YzFmN2M1YjkzYzQ0OTBhMTk4ZWVmNzg2YjQwNjJlODA3NjMG%0AOwBGSSIJY3NyZgY7AEZJIiU0Y2RkMWQ1ZGIyMjAzZWE5NjBlOGM2NzVlMjc2%0AZGMyOQY7AEZJIg10cmFja2luZwY7AEZ7B0kiFEhUVFBfVVNFUl9BR0VOVAY7%0AAFRJIi0xOGU0MGUxNDAxZWVmNjdlMWFlNjllZmFiMDlhZmI3MWY4N2ZmYjgx%0ABjsARkkiGUhUVFBfQUNDRVBUX0xBTkdVQUdFBjsAVEkiLWRhMzlhM2VlNWU2%0AYjRiMGQzMjU1YmZlZjk1NjAxODkwYWZkODA3MDkGOwBG%0A--15e3b749c97976c0f6c06b224d29434bdbe24275; path=/; HttpOnly\r\n"
-> "Via: 1.1 vegur\r\n"
-> "\r\n"
reading 131 bytes...
-> "<response><merchant>spreedly@robertevans.org-api</merchant><success>true</success><code></code><err></err><id>43638</id></response>"
read 131 bytes
Conn close
    )

  end

  def successful_auth_or_purchase_response
    "<response><merchant>spreedly@robertevans.org-api</merchant><success>true</success><code></code><err></err><id>40292</id></response>"
  end

  def failed_auth_or_purchase_response
    "<response><merchant>spreedly@robertevans.org-api</merchant><success>false</success><code>04</code><err>luhn</err><id>43616</id></response>"
  end

  def successful_capture_response
    "<response><merchant>spreedly@robertevans.org-api</merchant><success>true</success><code></code><err></err><id>43622</id></response>"
  end

  def failed_capture_response
    "<h1>Oops</h1><p class=\"lead\">Wow, it would be so handy if we told you what went wrong here.</p>"
  end

  def successful_refund_or_void_response
    "<response><merchant>spreedly@robertevans.org-api</merchant><success>true</success><code></code><err></err><id>43624</id></response>"
  end

  def failed_refund_or_void_response
    "<h1>Oops</h1><p class=\"lead\">Wow, it would be so handy if we told you what went wrong here.</p>"
  end

  def failed_purchase_because_of_pickup_card
    "<response><merchant>spreedly@robertevans.org-api</merchant><success>false</success><code>05</code><err>Sandbox error</err><id>43759</id></response>"
  end

  def failed_purchase_because_of_expired_card
    "<response><merchant>spreedly@robertevans.org-api</merchant><success>false</success><code>06</code><err>Sandbox error</err><id>43759</id></response>"
  end

  def failed_refund_because_of_bogus_ref_id
    "<response><merchant>spreedly@robertevans.org-api</merchant><success>false</success><code>07</code><err>Sandbox error</err><id>43759</id></response>"
  end
end
