require "heroku/command/pg"
require "heroku/command/pg_backups"
require "heroku/api"
require "tmpdir"
require "active_support/message_encryptor"
require "active_support/key_generator"

class PgbackupsArchive::Job

  attr_reader :client, :attrs
  attr_accessor :backup_url, :created_at

  def self.call(attrs={})
    new(attrs).call
  end

  def initialize(attrs={})
    Heroku::Command.load
    @attrs = attrs
    @client = Heroku::Command::Pg.new([], :app => app_name)
  end

  def call
    # expire  # Disabled b/c Heroku seems to be keeping only 2 on its own
    capture
    download
    encrypt
    archive
    delete
  end

  def archive
    if PgbackupsArchive::Storage.new(key, file, @attrs).store
      client.display "Backup archived"
    end
  end

  def capture
    attachment = client.send(:generate_resolver).resolve(database)
    backup = client.send(:hpg_client, attachment).backups_capture
    client.send(:poll_transfer, "backup", backup[:uuid])

    self.created_at = backup[:created_at]

    self.backup_url = Heroku::Client::HerokuPostgresqlApp
      .new(app_name).transfers_public_url(backup[:num])[:url]
  end

  def delete
    File.delete(temp_file)
  end

  def download
    File.open(temp_file, "wb") do |output|
      streamer = lambda do |chunk, remaining_bytes, total_bytes|
        output.write chunk
      end

      # https://github.com/excon/excon/issues/475
      Excon.get backup_url,
        :response_block    => streamer,
        :omit_default_port => true
    end
  end

  def encrypt
    return unless @attrs[:enc_password].present? && @attrs[:enc_salt].present?

    key = ActiveSupport::KeyGenerator.new(@attrs[:enc_password]).generate_key(@attrs[:enc_salt])
    crypt = ActiveSupport::MessageEncryptor.new(key)
    encrypted_data = crypt.encrypt_and_sign(File.read(temp_file))
    File.open(temp_file, "w") { |output| output.write encrypted_data }
  end

  def expire
    transfers = client.send(:hpg_app_client, app_name).transfers
      .select  { |b| b[:from_type] == "pg_dump" && b[:to_type] == "gof3r" }
      .sort_by { |b| b[:created_at] }

    if transfers.size > pgbackups_to_keep
      backup_id  = "b%03d" % transfers.first[:num]
      backup_num = client.send(:backup_num, backup_id)

      expire_backup(backup_num)

      client.display "Backup #{backup_id} expired"
    end
  end

  private

  def expire_backup(backup_num)
    client.send(:hpg_app_client, app_name)
      .transfers_delete(backup_num)
  end

  def database
    ENV["PGBACKUPS_DATABASE"] || "DATABASE_URL"
  end

  def environment
    defined?(Rails) ? Rails.env : nil
  end

  def file
    File.open(temp_file, "r")
  end

  def key
    timestamp = created_at.gsub(/\/|\:|\.|\s\+/, "-").concat(".dump")
    ["backups", "pgbackups", timestamp].compact.join("/")
  end

  def pgbackups_to_keep
    var = ENV["PGBACKUPS_KEEP"] ? ENV["PGBACKUPS_KEEP"].to_i : 30
  end

  def temp_file
    "#{Dir.tmpdir}/pgbackup"
  end

  def app_name
    @attrs[:app_name] || ENV["PGBACKUPS_APP"]
  end

end
