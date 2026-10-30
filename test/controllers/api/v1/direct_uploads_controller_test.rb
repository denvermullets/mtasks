require 'test_helper'

module Api
  module V1
    class DirectUploadsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(name: 'API User', email: 'api_uploads@example.com', password: 'password')
        @headers = api_headers_for(@user)
      end

      def blob_body(content_type: 'image/png', byte_size: 1024, filename: 'a.png')
        { blob: { filename: filename, byte_size: byte_size, checksum: Base64.strict_encode64('x' * 16),
                  content_type: content_type } }.to_json
      end

      test 'returns signed id and upload target' do
        assert_difference -> { ActiveStorage::Blob.count }, 1 do
          post api_v1_direct_uploads_path, params: blob_body, headers: @headers
        end

        assert_response :success
        json = response.parsed_body
        assert json['signed_id'].present?
        assert_equal 'a.png', json['filename']
        assert json.dig('direct_upload', 'url').present?
        assert_kind_of Hash, json.dig('direct_upload', 'headers')
      end

      test 'accepts documents beyond images up to the cap' do
        post api_v1_direct_uploads_path,
             params: blob_body(content_type: 'application/pdf', byte_size: 25.megabytes, filename: 'a.pdf'),
             headers: @headers

        assert_response :success
      end

      test 'rejects disallowed content type' do
        assert_no_difference -> { ActiveStorage::Blob.count } do
          post api_v1_direct_uploads_path, params: blob_body(content_type: 'image/svg+xml'), headers: @headers
        end

        assert_response :unprocessable_entity
      end

      test 'rejects oversize and empty files' do
        [25.megabytes + 1, 0].each do |size|
          post api_v1_direct_uploads_path, params: blob_body(byte_size: size), headers: @headers

          assert_response :unprocessable_entity
        end
      end

      test 'requires a token' do
        post api_v1_direct_uploads_path, params: blob_body, headers: { 'Content-Type' => 'application/json' }

        assert_response :unauthorized
      end

      test 'read-only token is forbidden' do
        token = ApiToken.generate_for(@user, name: 'RO', scopes: %w[read])
        headers = { 'Authorization' => "Bearer #{token.raw_token}", 'Content-Type' => 'application/json' }

        post api_v1_direct_uploads_path, params: blob_body, headers: headers

        assert_response :forbidden
      end
    end
  end
end
