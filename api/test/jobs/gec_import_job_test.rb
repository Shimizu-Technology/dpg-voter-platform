require "test_helper"

class GecImportJobTest < ActiveSupport::TestCase
  test "marks import completed only after artifact preservation" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "voter_list.csv",
      import_type: "full_list",
      status: "pending",
      metadata: { "stage" => "queued", "progress_percent" => 0 }
    )
    upload = GecImportUpload.create!(
      gec_import: gec_import,
      filename: "voter_list.csv",
      content_type: "text/csv",
      file_data: "First Name,Last Name,Village\nJuan,Cruz,Barrigada\n"
    )

    fake_service = Object.new
    fake_service.define_singleton_method(:call) do
      gec_import.update!(
        status: "processing",
        total_records: 1,
        new_records: 1,
        metadata: { "stage" => "finalizing_artifact", "progress_percent" => 95 }
      )

      GecImportService::Result.new(
        success: true,
        gec_import: gec_import,
        errors: [],
        stats: { total: 1, new: 1 }
      )
    end

    uploaded = []
    upload_stub = lambda do |key, data, **kwargs|
      body = data.respond_to?(:read) ? data.read : data
      data.rewind if data.respond_to?(:rewind)
      uploaded << { key: key, data: body, kwargs: kwargs }
      key
    end

    service_singleton = class << GecImportService; self; end
    service_original_new = service_singleton.instance_method(:new) if service_singleton.method_defined?(:new)
    s3_singleton = class << S3Service; self; end
    s3_original_enabled = s3_singleton.instance_method(:enabled?) if s3_singleton.method_defined?(:enabled?)
    s3_original_upload = s3_singleton.instance_method(:upload) if s3_singleton.method_defined?(:upload)

    service_singleton.define_method(:new) { |*args, **kwargs| fake_service }
    s3_singleton.define_method(:enabled?) { true }
    s3_singleton.define_method(:upload) { |*args, **kwargs| upload_stub.call(*args, **kwargs) }

    GecImportJob.perform_now(
      gec_import_id: gec_import.id,
      upload_id: upload.id,
      gec_list_date: "2026-02-25"
    )

    gec_import.reload
    assert_equal "completed", gec_import.status
    assert_equal "completed", gec_import.metadata["stage"]
    assert_equal 100, gec_import.metadata["progress_percent"]
    assert_not_nil gec_import.original_file_s3_key
    assert uploaded.any? { |entry| entry[:key].include?("/artifact/") }
  ensure
    if defined?(service_singleton)
      service_singleton.send(:remove_method, :new) if service_singleton.method_defined?(:new)
      service_singleton.define_method(:new, service_original_new) if defined?(service_original_new) && service_original_new
    end
    if defined?(s3_singleton)
      s3_singleton.send(:remove_method, :enabled?) if s3_singleton.method_defined?(:enabled?)
      s3_singleton.define_method(:enabled?, s3_original_enabled) if defined?(s3_original_enabled) && s3_original_enabled
      s3_singleton.send(:remove_method, :upload) if s3_singleton.method_defined?(:upload)
      s3_singleton.define_method(:upload, s3_original_upload) if defined?(s3_original_upload) && s3_original_upload
    end
  end

  test "does not preserve import artifact when import service fails" do
    gec_import = GecImport.create!(
      gec_list_date: Date.new(2026, 2, 25),
      filename: "voter_list.csv",
      import_type: "full_list",
      status: "pending",
      metadata: { "stage" => "queued", "progress_percent" => 0 }
    )
    upload = GecImportUpload.create!(
      gec_import: gec_import,
      filename: "voter_list.csv",
      content_type: "text/csv",
      file_data: "First Name,Last Name,Village\nJuan,Cruz,Barrigada\n"
    )

    fake_service = Object.new
    fake_service.define_singleton_method(:call) do
      GecImportService::Result.new(
        success: false,
        gec_import: gec_import,
        errors: [ "simulated import failure" ],
        stats: {}
      )
    end

    uploaded = []
    upload_stub = lambda do |key, data, **kwargs|
      uploaded << { key: key, data: data, kwargs: kwargs }
      key
    end

    with_singleton_stubs(GecImportService, new: fake_service) do
      with_singleton_stubs(S3Service, enabled?: true, upload: upload_stub) do
        GecImportJob.perform_now(
          gec_import_id: gec_import.id,
          upload_id: upload.id,
          gec_list_date: "2026-02-25"
        )
      end
    end

    gec_import.reload
    assert_equal "failed", gec_import.status
    assert_nil gec_import.original_file_s3_key
    assert_nil uploaded.find { |entry| entry[:key].include?("/artifact/") }
  end

  private

  def with_singleton_stubs(klass, stubs)
    singleton = class << klass; self; end
    originals = {}

    stubs.each do |method_name, replacement|
      originals[method_name] = singleton.instance_method(method_name) if singleton.method_defined?(method_name)
      singleton.define_method(method_name) do |*args, **kwargs, &block|
        if replacement.respond_to?(:call)
          replacement.call(*args, **kwargs, &block)
        else
          replacement
        end
      end
    end

    yield
  ensure
    stubs.each_key do |method_name|
      singleton.send(:remove_method, method_name) if singleton.method_defined?(method_name)
      singleton.define_method(method_name, originals[method_name]) if originals[method_name]
    end
  end
end
