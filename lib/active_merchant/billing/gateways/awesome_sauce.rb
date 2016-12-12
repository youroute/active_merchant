require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class AwesomeSauceGateway < Gateway
      self.test_url = 'http://sandbox.asgateway.com'
      self.live_url = 'https://prod.awesomesauce.example.com'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.supported_cardtypes = [:visa, :master, :american_express]

      self.homepage_url = 'http://asgateway.com'
      self.display_name = 'Awesomesauce'

      STANDARD_ERROR_CODE_MAPPING = {
        'config' => {:code => STANDARD_ERROR_CODE[:config_error], :msg => "Bad credentials"},
        'unknown' => {:code => STANDARD_ERROR_CODE[:processing_error], :msg => "Unknown error" },
        'luhn' => {:code => STANDARD_ERROR_CODE[:incorrect_number], :msg => "Fails luhn check"},
        'number' => {:code => STANDARD_ERROR_CODE[:invalid_number], :msg => "Invalid CC number"},
        'cv2' => {:code => STANDARD_ERROR_CODE[:invalid_cvc], :msg => "Invalid CVC"},
        'exp' => {:code => STANDARD_ERROR_CODE[:invalid_expiry_date], :msg => "Invalid expiry"},
        'amount' => {:code => STANDARD_ERROR_CODE[:processing_error], :msg => "Bad amount" },
        '05' => {:code => STANDARD_ERROR_CODE[:pickup_card], :msg => "Pickup Card" },
        '06' => {:code => STANDARD_ERROR_CODE[:expired_card], :msg => "Expired Card" },
        '07' => {:code =>  STANDARD_ERROR_CODE[:processing_error], :msg => "Bad ref id"},
      }

      ENDPOINT_PATH = 'api'

      ENDPOINT_BASENAMES = {
        sale: "auth",
        authonly: "auth",
        capture: "ref",
        void: "ref",
        refund: "ref",
      }

      ACTIONS = {
        sale: "purch",
        authonly: "auth",
        capture: "capture",
        void: "cancel",
        refund: "cancel",
      }

      def initialize(options={})
        requires!(options, :login, :password)
        super
      end

      def purchase(money, payment, options={})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, payment, options)

        commit(:sale, post)
      end

      def authorize(money, payment, options={})
        post = {}
        add_invoice(post, money, options)
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, payment, options)

        commit(:authonly, post)
      end

      def capture(money, authorization, options={})
        post = {}
        add_authorization(post, authorization)
        commit(:capture, post)
      end

      def refund(money, authorization, options={})
        post = {}
        add_authorization(post, authorization)
        commit(:refund, post)
      end

      def void(authorization, options={})
        post = {}
        add_authorization(post, authorization)
        commit(:void, post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((<number>).+(</number>)), '\1[FILTERED]\2').
          gsub(%r((<cv2>).+(</cv2>)), '\1[FILTERED]\2').
          gsub(%r((<secret>).+(</secret)), '\1[FILTERED]\2')
      end

      private

      def add_customer_data(post, creditcard, options)
        post[:name] = (options[:customer] || creditcard.name? && creditcard.name)
      end

      def add_address(post, creditcard, options)
      end

      def add_invoice(post, money, options)
        post[:amount] = amount(money)
        post[:currency] = (options[:currency] || currency(money))
      end

      def add_payment(post, creditcard)
        post[:number] = creditcard.number
        post[:cv2] = creditcard.verification_value
        post[:exp] = creditcard.expiry_date.expiration.strftime("%m%Y")
      end

      def add_authorization(post, authorization)
        transaction_id, _ = split_authorization(authorization)
        post[:ref] = transaction_id
      end

      def parse(body, action)
        doc = Nokogiri::XML(body)

        response = {}
        response[:error_code] = 'unknown'

        if(element = doc.at_xpath("/error"))
          response[:error_code] = 'config'
          response[:response_text] = element.content
        elsif(element = doc.at_xpath("/response/success"))
          if(element.content == 'true')
            response[:transaction_id] = doc.at_xpath("/response/id").content
            response[:response_text] = "#{action} succeeded"
            response.delete(:error_code)
          elsif(element.content == 'false')
            raw_code = doc.at_xpath("/response/code").content
            raw_error = doc.at_xpath("/response/err").content
            response[:error_code] =
              case raw_code
              when "03"
                case raw_error
                when "number", "cv2", "exp", "amount"
                  raw_error
                else
                  "unknown"
                end
              when "04"
                case raw_error
                when "luhn"
                  raw_error
                else
                  "unknown"
                end
              when "05", "06", "07"
                raw_code
              else
                "unknown"
              end
          end
        elsif(element = doc.at_xpath("/h1"))
          if(element.content == 'Oops')
            response[:response_text] = "#{action} failed"
          end
        end

        response
      end

      def url(action)
         base_url = test? ? test_url : live_url
         "#{base_url}/#{ENDPOINT_PATH}/#{ENDPOINT_BASENAMES[action]}"
      end

      def commit(action, parameters)
        begin
          raw_response = ssl_post(url(action), post_data(action, parameters))
          response = parse(raw_response, action)
        rescue ResponseError => e
          raise unless(e.response.code.to_s =~ /[45]\d\d/)
          response = parse(e.response.body, action)
        end

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(action, response),
          avs_result: AVSResult.new(code: response["some_avs_response_key"]),
          cvv_result: CVVResult.new(response["some_cvv_response_key"]),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
        response.key?(:transaction_id)
      end

      def message_from(response)
        response[:response_text] || STANDARD_ERROR_CODE_MAPPING["#{response[:error_code]}"][:msg]
      end

      def authorization_from(action, response)
        [response[:transaction_id], action].join("#")
      end

      def split_authorization(authorization)
        authorization.split("#")
      end

      def post_data(action, parameters = {})
        Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
          xml.send('request') do
            xml.action(ACTIONS[action])
            add_authentication(xml)
            parameters.each { |key, value| xml.parent << Nokogiri.XML('').create_element(key.to_s, value) }
          end
        end.to_xml(indent: 0)
      end

      def add_authentication(xml)
        xml.merchant(@options[:login])
        xml.secret(@options[:password])
      end

      def error_code_from(response)
        unless success_from(response)
          STANDARD_ERROR_CODE_MAPPING["#{response[:error_code]}"][:code]
        end
      end
    end
  end
end
