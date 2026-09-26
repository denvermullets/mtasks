require 'test_helper'

class ImageUploadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: 'Ryan', email: "uploads-#{SecureRandom.hex(4)}@example.com", password: 'password')
  end

  def blob_params(content_type: 'image/png', byte_size: 1024)
    { blob: { filename: 'image.png', byte_size: byte_size, checksum: Base64.strict_encode64('x' * 16),
              content_type: content_type } }
  end

  test 'creates a blob for a signed-in user pasting an image' do
    sign_in_as(@user)

    assert_difference -> { ActiveStorage::Blob.count }, 1 do
      post image_uploads_path, params: blob_params, as: :json
    end

    assert_response :success
    assert response.parsed_body['signed_id'].present?
    assert response.parsed_body.dig('direct_upload', 'url').present?
  end

  test 'requires a session' do
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post image_uploads_path, params: blob_params, as: :json
    end

    assert_redirected_to new_session_path
  end

  test 'rejects non-images' do
    sign_in_as(@user)

    assert_no_difference -> { ActiveStorage::Blob.count } do
      post image_uploads_path, params: blob_params(content_type: 'application/pdf'), as: :json
    end

    assert_response :unprocessable_content
  end

  test 'rejects images over the size cap' do
    sign_in_as(@user)

    assert_no_difference -> { ActiveStorage::Blob.count } do
      post image_uploads_path, params: blob_params(byte_size: 11.megabytes), as: :json
    end

    assert_response :unprocessable_content
  end
end
