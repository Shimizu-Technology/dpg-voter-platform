# frozen_string_literal: true

class GecPdfPreviewCleanupJob < ApplicationJob
  queue_as :default

  def perform
    GecPdfPreview.purge_stale!
  end
end
