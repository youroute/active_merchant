require 'test_helper'

class RemoteAwesomeSauceTest < Test::Unit::TestCase
  def setup
    @gateway = AwesomeSauceGateway.new(fixtures(:awesome_sauce))

    @amount = 100
    @credit_card = credit_card('4000100011112224')

    @bad_luhn = credit_card('4000300011112225')
    @bad_number = credit_card("string")
    @bad_cvc = credit_card('4000100011112224', {:verification_value => ''})
    @bad_expiry = credit_card('4000100011112224', {:year => '10000'})

    @options = {
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_successful_purchase
    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'sale succeeded', response.message
  end

  def test_successful_purchase_with_more_options
    options = {
      order_id: '1',
      ip: "127.0.0.1",
      email: "joe@example.com"
    }

    response = @gateway.purchase(@amount, @credit_card, options)
    assert_success response
    assert_equal 'sale succeeded', response.message
  end

  def test_failed_purchase
    response = @gateway.purchase(100, @bad_luhn, @options)
    assert_failure response
    assert_equal 'Fails luhn check', response.message
    assert_equal 'incorrect_number', response.error_code
  end

  def test_failed_purchase_bad_amount
    response = @gateway.purchase(-100, @credit_card, @options)
    assert_failure response
    assert_equal 'Bad amount', response.message
  end

  def test_failed_purchase_bad_expiry
    response = @gateway.purchase(@amount, @bad_expiry, @options)
    assert_failure response
    assert_equal 'Invalid expiry', response.message
  end

  def test_failed_purchase_bad_cvc
    response = @gateway.purchase(@amount, @bad_cvc, @options)
    assert_failure response
    assert_equal 'Invalid CVC', response.message
  end

  def test_successful_authorize_and_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'authonly succeeded', auth.message

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
    assert_equal 'capture succeeded', capture.message
  end

  def test_partial_capture
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert capture = @gateway.capture(@amount-1, auth.authorization)
    assert_success capture
    assert_equal 'capture succeeded', capture.message
  end

  def test_failed_capture
    response = @gateway.capture(@amount, '')
    assert_failure response
    assert_equal 'capture failed', response.message
  end

  def test_successful_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount, purchase.authorization)
    assert_success refund
    assert_equal 'refund succeeded', refund.message
  end

  def test_partial_refund
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount-1, purchase.authorization)
    assert_success refund
    assert_equal 'refund succeeded', refund.message
  end

  def test_failed_refund
    response = @gateway.refund(@amount, '')
    assert_failure response
    assert_equal 'refund failed', response.message
  end

  def test_bad_transaction_id
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    assert refund = @gateway.refund(@amount, "1#what")
    assert_failure refund
    assert_equal 'refund failed', refund.message
  end

  def test_simulated_pickup_card
    simulated_refund = @gateway.purchase(105, @credit_card, @options)

    assert_failure simulated_refund
    assert_equal 'Pickup Card', simulated_refund.message
  end

  def test_simulated_expired_card
    simulated_refund = @gateway.purchase(106, @credit_card, @options)

    assert_failure simulated_refund
    assert_equal 'Expired Card', simulated_refund.message
  end

  def test_simulated_bad_ref_id
    simulated_refund = @gateway.purchase(107, @credit_card, @options)

    assert_failure simulated_refund
    assert_equal 'Bad ref id', simulated_refund.message
  end

  def test_successful_void
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    assert void = @gateway.void(auth.authorization)
    assert_success void
    assert_equal 'void succeeded', void.message
  end

  def test_failed_void
    response = @gateway.void('')
    assert_failure response
    assert_equal 'void failed', response.message
  end

  def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
    assert_match %r{succeeded}, response.message
  end

  def test_failed_verify_bad_number
    response = @gateway.verify(@bad_number, @options)
    assert_failure response
    assert_equal 'Invalid CC number', response.message
  end

  def test_invalid_login
    gateway = AwesomeSauceGateway.new(login: '', password: '')

    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_match %r{Invalid security}, response.message
  end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end
    transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, transcript)
    assert_scrubbed(@credit_card.verification_value, transcript)
    assert_scrubbed(@gateway.options[:password], transcript)
  end

end
