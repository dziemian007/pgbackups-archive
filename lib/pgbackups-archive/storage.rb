require "fog/aws"
require "open-uri"

class PgbackupsArchive::Storage

  def initialize(key, file, config = {})
    @key = key
    @file = file
    @config = config
  end

  def connection
    Fog::Storage.new({
      :provider              => "AWS",
      :aws_access_key_id     => @config[:aws_access_key_id] || ENV["PGBACKUPS_AWS_ACCESS_KEY_ID"],
      :aws_secret_access_key => @config[:aws_secret_access_key] || ENV["PGBACKUPS_AWS_SECRET_ACCESS_KEY"],
      :region                => @config[:aws_region] || ENV["PGBACKUPS_REGION"],
      :persistent            => false
    })
  end

  def bucket
    connection.directories.get @config[:aws_bucket] || ENV["PGBACKUPS_BUCKET"]
  end

  def store
    bucket.files.create :key => @key, :body => @file, :public => false, :encryption => "AES256"
  end

end
