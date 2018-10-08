class TransmissionApi::Client
  attr_accessor :session_id
  attr_accessor :url
  attr_accessor :basic_auth
  attr_accessor :fields
  attr_accessor :session_fields
  attr_accessor :debug_mode
  attr_accessor :with_extra

  STATUS_STOPPED       : 0  # Torrent is stopped
  STATUS_CHECK_WAIT    : 1  # Queued to check files
  STATUS_CHECK         : 2  # Checking files
  STATUS_DOWNLOAD_WAIT : 3  # Queued to download
  STATUS_DOWNLOAD      : 4  # Downloading
  STATUS_SEED_WAIT     : 5  # Queued to seed
  STATUS_SEED          : 6  # Seeding
  STATUS_ISOLATED      : 7  # Torrent can't find peers

  TORRENT_FIELDS = [
    "id",
    "name",
    "totalSize",
    "addedDate",
    "status",
    "rateDownload",
    "rateUpload",
    "percentDone",
    "hashString",
    "files"
  ]

  TORRENT_EXTRA_FIELDS = [
    "downloadDir",
    "error",
    "errorString",
    "eta",
    "isFinished"
    "isStalled",
    "leftUntilDone",
    "metadataPercentComplete",
    "peersConnected",
    "peersGettingFromUs",
    "peersSendingToUs",
    "queuePosition",
    "recheckProgress",
    "seedRatioLimit",
    "seedRatioMode",
    "sizeWhenDone",
    "status",
    "trackers",
    "uploadRatio",
    "uploadedEver",
    "webseedsSendingToUs",
    "id",
    "activityDate",
    "corruptEver",
    "desiredAvailable",
    "downloadedEver",
    "fileStats",
    "haveUnchecked",
    "haveValid",
    "peers",
    "startDate",
    "trackerStats",
    "hashString"
  ]

  SESSION_FIELDS = [
    "download-dir",
    "download-dir-free-space",
    "config-dir",
    "peer-port",
    "peer-port-random-on-start",
    "speed-limit-down",
    "speed-limit-down-enabled",
    "speed-limit-up",
    "speed-limit-up-enabled",
  ]

  SESSION_EXTRA_FIELDS = [
    "alt-speed-down",
    "alt-speed-enabled",
    "alt-speed-time-begin",
    "alt-speed-time-day",
    "alt-speed-time-enabled",
    "alt-speed-time-end",
    "alt-speed-up",
    "blocklist-enabled",
    "blocklist-size",
    "blocklist-url",
    "cache-size-mb",
    "dht-enabled",
    "download-queue-enabled",
    "download-queue-size",
    "encryption",
    "idle-seeding-limit",
    "idle-seeding-limit-enabled",
    "incomplete-dir",
    "incomplete-dir-enabled",
    "lpd-enabled",
    "peer-limit-global",
    "peer-limit-per-torrent",
    "pex-enabled",
    "port-forwarding-enabled",
    "queue-stalled-enabled",
    "queue-stalled-minutes",
    "rename-partial-files",
    "rpc-version",
    "rpc-version-minimum",
    "script-torrent-done-enabled",
    "script-torrent-done-filename",
    "seed-queue-enabled",
    "seed-queue-size",
    "seedRatioLimit",
    "seedRatioLimited",
    "start-added-torrents",
    "trash-original-torrent-files",
    "units",
    "utp-enabled"
  ]

  def initialize(opts)
    @url = opts[:url]
    @with_extra = opts[:with_extra] || false
    @fields = opts[:fields] || TORRENT_FIELDS
    if @with_extra then
      @fields |= TORRENT_EXTRA_FIELDS
    end
    @basic_auth = { :username => opts[:username], :password => opts[:password] } if opts[:username]
    @session_id = "NOT-INITIALIZED"
    @debug_mode = opts[:debug_mode] || false
  end

  def all(opts = {})
    log "get_torrents"

    unless opts[:fields].nil? do
      fields = opts[:fields]
    end

    response = post(
        :method => "torrent-get",
        :arguments => {
          :fields => fields
        }
      )

    response["arguments"]["torrents"]
  end

  def find_each
    torrent_ids = post(
      :method => "torrent-get",
      :arguments => {
        :fields => ["id"]
      }
    )
    torrent_ids["arguments"]["torrents"].each do | t |
      torrent = find(t['id'])
      yield(torrent)
    end
  end

  def find(id)
    log "get_torrent: #{id}"

    response =
      post(
        :method => "torrent-get",
        :arguments => {
          :fields => fields,
          :ids => [id]
        }
      )

    response["arguments"]["torrents"].first
  end

  def find_by_hash(hash)
    log "get_torrent_by_hash#{hash}"
    response = all
    response.select{| torrent | torrent["hashString"] == hash}.first
  end

  def create(filename)
    log "add_torrent: #{filename}"

    response =
      post(
        :method => "torrent-add",
        :arguments => {
          :filename => filename
        }
      )
    response["arguments"]["torrent-added"]
  end

  def start(id)
    log "start_torrent: #{id}"

    response =
      post(
        :method => "torrent-start",
        :arguments => {
          :ids => [id]
        }
      )
  end

  def stop(id)
    log "stop_torrent: #{id}"

    response =
      post(
        :method => "torrent-stop",
        :arguments => {
          :ids => [id]
        }
      )
    response
  end

  def destroy(id, trashdata = false)
    log "remove_torrent: #{id}"

    response =
      post(
        :method => "torrent-remove",
        :arguments => {
          :ids => [id],
          :"delete-local-data" => trashdata
        }
      )

    response
  end

  def config_get
    log "load_config"

    response =
      post(
        :method => "session-get",
      )

    response["arguments"]
  end

  def config_set(config)
    log "set_config #{config}"

    response =
      post(
        :method => "session-set",
        :arguments => config
      )

    response
  end

  def post(opts)
    response_parsed = JSON::parse( http_post(opts).body )

    if response_parsed["result"] != "success"
      raise TransmissionApi::Exception, response_parsed["result"]
    end

    response_parsed
  end

  def http_post(opts)
    post_options = {
      :body => opts.to_json,
      :headers => { "x-transmission-session-id" => session_id }
    }
    post_options.merge!( :basic_auth => basic_auth ) if basic_auth

    log "url: #{url}"
    log "post_body:"
    log JSON.parse(post_options[:body]).to_yaml
    log "------------------"

    response = HTTParty.post( url, post_options )

    log_response response

    # retry connection if session_id incorrect
    if( response.code == 409 )
      log "changing session_id"
      @session_id = response.headers["x-transmission-session-id"]
      response = http_post(opts)
    end

    response
  end

  def log(message)
    Kernel.puts "[TransmissionApi #{Time.now.strftime( "%F %T" )}] #{message}" if debug_mode
  end

  def log_response(response)
    body = nil
    begin
      body = JSON.parse(response.body).to_yaml
    rescue
      body = response.body
    end

    headers = response.headers.to_yaml

    log "response.code: #{response.code}"
    log "response.message: #{response.message}"

    log "response.body_raw:"
    log response.body
    log "-----------------"

    log "response.body:"
    log body
    log "-----------------"

    log "response.headers:"
    log headers
    log "------------------"
  end
end
