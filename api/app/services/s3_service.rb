# frozen_string_literal: true

class S3Service
  BUCKET_NAME = ENV.fetch("AWS_S3_BUCKET", nil)
  REGION = ENV.fetch("AWS_REGION", "ap-southeast-2")

  MUTEX = Mutex.new

  class << self
    def safe_filename(filename, fallback: "import_file")
      safe = filename.to_s.gsub(/[^A-Za-z0-9._\-]/, "_").squeeze("_")
      safe.present? ? safe : fallback
    end

    def enabled?
      BUCKET_NAME.present? &&
        ENV["AWS_ACCESS_KEY_ID"].present? &&
        ENV["AWS_SECRET_ACCESS_KEY"].present?
    end

    def s3_client
      return @s3_client if @s3_client

      MUTEX.synchronize do
        @s3_client ||= Aws::S3::Client.new(
          region: REGION,
          access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID"),
          secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY")
        )
      end
    end

    # Upload file data (String or IO-like body) to S3
    def upload(key, data, content_type: "application/octet-stream")
      return nil unless enabled?

      s3_client.put_object(
        bucket: BUCKET_NAME,
        key: key,
        body: data,
        content_type: content_type,
        server_side_encryption: "AES256"
      )
      key
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error "[S3Service] Upload failed for #{key}: #{e.message}"
      nil
    end

    def download(key)
      return nil unless enabled?

      response = s3_client.get_object(bucket: BUCKET_NAME, key: key)
      response.body.read
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error "[S3Service] Download failed for #{key}: #{e.message}"
      nil
    end

    def download_to_io(key, io)
      return false unless enabled?

      s3_client.get_object(bucket: BUCKET_NAME, key: key, response_target: io)
      io.flush if io.respond_to?(:flush)
      true
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error "[S3Service] Stream download failed for #{key}: #{e.message}"
      false
    end

    # Generate a presigned GET URL for temporary file access.
    def presigned_url(key, expires_in: 3600, filename: nil, disposition: :attachment)
      return nil unless enabled?

      presigner = Aws::S3::Presigner.new(client: s3_client)
      options = {
        bucket: BUCKET_NAME,
        key: key,
        expires_in: expires_in
      }
      if filename.present?
        escaped = filename.to_s.gsub(/["\\]/) { |ch| "\\#{ch}" }
        mode = disposition.to_sym == :inline ? "inline" : "attachment"
        options[:response_content_disposition] = "#{mode}; filename=\"#{escaped}\""
      end
      presigner.presigned_url(:get_object, **options)
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error "[S3Service] Presigned URL failed for #{key}: #{e.message}"
      nil
    end

    # Delete an object from S3
    def delete(key)
      return true unless enabled?

      s3_client.delete_object(bucket: BUCKET_NAME, key: key)
      true
    rescue Aws::S3::Errors::ServiceError => e
      Rails.logger.error "[S3Service] Delete failed for #{key}: #{e.message}"
      false
    end
  end
end
