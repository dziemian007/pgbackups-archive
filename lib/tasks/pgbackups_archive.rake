namespace :pgbackups do

  desc 'Capture a Heroku PGBackups backup and archive it to Amazon S3.'
  task :archive do
    PgbackupsArchive::Job.call({
      heroku_api_key: ENV['HEROKU_API_KEY'],
      app_name: ENV['APP_NAME'],
      aws_access_key_id: ENV['S3_KEY'],
      aws_secret_access_key: ENV['S3_SECRET'],
      aws_bucket: ENV['S3_BUCKET_NAME'],
      aws_region: 'eu-west-1'
    })
  end

end
