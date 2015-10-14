#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'rest-client'
require 'cgi'
require 'open-uri'
require 'rdf'
require 'linkeddata'
require 'logger'
require 'yaml'
require 'fileutils'

@config = YAML.load_file('data.yaml')

@logger = Logger.new(STDOUT)
@logger.level = Logger::INFO
@logger.formatter = proc do |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
end

@host = @config['dspacedata']['host']

# Login to DSpace
def login_dspace

  dspaceuser = @config['dspacedata']['email']
  pwd = @config['dspacedata']['password']

  begin
    response = RestClient.post("#{@host}/rest/login", {"email" => "#{dspaceuser}", "password" => "#{pwd}"}.to_json,
                               {:content_type => 'application/json',
                                :accept => 'application/json'})
    @login_token = response.to_str
    @logger.info "Your login token is: #{@login_token}"

  rescue => e
    @logger.fatal("Cannot log into DSpace (#{e})")
  end
end



# Log in to SEAD
def login_sead
  @host_sead = @config['seaddata']['host']
  seaduser = @config['seaddata']['email']
  pwd = @config['seaddata']['password']

  begin
    response = RestClient.post("#{@host_sead}", {"email" => "#{seaduser}", "password" => "#{pwd}"}.to_json,
                               {:content_type => 'application/json',
                                :accept => 'application/json'})

    @logger.info(response.code)

  rescue => e
    @logger.fatal("Cannot log into SEAD (#{e})")
  end
end


# Creates item and posts ORE for the item
def create_item (id, title, abstract, creator, rights, date, orefile)

  # Create an item
  @logger.info("Creating an item")
  response = RestClient.post("#{@host}/rest/collections/116/items",{"type" => "item"}.to_json,
                         {:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })


  @logger.info("Response status: #{response.code}")
  item = JSON.parse(response)
  itemid = "#{item["id"]}"
  itemhandle = "#{item["handle"]}"
  @logger.info("Item ID is: #{itemid}")


  # update item metadata
  metadata = [{"key"=>"dc.identifier", "value"=>"#{id}", "language"=>"en"},{"key"=>"dc.date", "value"=>"#{date}", "language"=>"en"},{"key"=>"dc.title", "value"=>"#{title}", "language"=>"en"},{"key"=>"dc.description.abstract", "value"=>"#{abstract}", "language"=>"en"},{"key"=>"dc.creator", "value"=>"#{creator}", "language"=>"en"}, {"key"=>"dc.rights", "value"=>"#{rights}", "language"=>"en"}]

  aggmetadata = RestClient.put("#{@host}/rest/items/#{itemid}/metadata", "#{metadata.to_json}",
                               {:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })

  @logger.info("Response status: #{aggmetadata.code}")


  # post orefile
  response = RestClient.post("#{@host}/rest/items/#{itemid}/bitstreams?name=#{title.gsub(' ', '_')}.jsonld&description=ORE_file",
                            {
                                :transfer =>{
                                    :type => 'bitstream'
                                },
                                :upload => {
                                    :file => File.new("#{orefile}",'rb')
                                }
                            } ,
                            {:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })

  # Update bitstream metadata
  # ore_metadata = JSON.parse(response)
  # ore_id = "#{ore_metadata["id"]}"
  # p ore_id
  #
  # update_aggmetadata = RestClient.put("#{@host}/rest/bitstreams/#{ore_id}", [{"format" => "JSON-LD"}, {"mimeType"=>"application/ld+json"}].to_json,
  #                                     {:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })
  # p update_aggmetadata.to_str
  # @logger.info "Response status: #{update_aggmetadata.code}"

  @logger.info "Response status: #{response.code}"

  unless "#{response.code}" == "200"
    @logger.fatal "ORE ingestion failed! (#{response})"
    return -1, -1
  end

  @logger.info "Handle is: #{itemhandle}"
  return itemid, itemhandle
end

def update_item(itemid, bitstream, title, mime, date)
  # code here
  response = RestClient.post("#{@host}/rest/items/#{itemid}/bitstreams?name=#{title.gsub(' ', '_')}",
                            {
                                :transfer =>{
                                    :type => 'bitstream'
                                },
                                :upload => {
                                    :file => File.new("#{bitstream}",'rb')
                                }
                            } ,{:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })

  unless "#{response.code}" == "200"
    @logger.fatal "ORE ingestion failed! (#{response})"
  end
end

def update_status(stage, message, updatestatus_url)
  begin
    RestClient.post("#{updatestatus_url}", {"reporter" => "ideals", "stage" => stage, "message" => message}.to_json, {:content_type => :json, :accept => :json})
  rescue => e
    p "ERROR: Cannot update status at #{updatestatus_url} (#{e})"
  end
end


# Main

login_dspace
login_sead

# Get the list of all research objects for ideals
researchobjects = RestClient.get @config['seaddata']['ro_list']
researchobjects_parsed = JSON.parse(researchobjects)

# p researchobjects_parsed

researchobjects_parsed.each do |researchobject|
  agg_id = "#{researchobject['Aggregation']['Identifier']}"


  old_item = false
  researchobject['Status'].each do |status|
    old_item = true unless status['stage'] == "Receipt Acknowledged" && status['reporter'] == "SEAD-CP"
  end


  if old_item then
    @logger.warn("Skipping #{agg_id}. Current status: stage = #{researchobject['Status'].last['stage']}, reporter = #{researchobject['Status'].last['reporter']}")
    next
  else

    agg_id_escaped = CGI.escape(agg_id)
    # p agg_id_escaped
    ro_url = @config['seaddata']['ro_ore'] + agg_id_escaped

    # p 'Retreive Research Object from this link: '+ ro_url

    updatestatus_url = @config['seaddata']['ro_ore'] + "#{agg_id_escaped}/status"
    message = "Processing research object"
    stage = "Pending"
    # update_status(stage, message, updatestatus_url)

    ro_json = RestClient.get ro_url
    # p ro_json

    if ro_json.code != 200
      p "ERROR: Invalid URL #{ro_url} -- #{ro_json.code}"
      next
    end

    ro = JSON.parse(ro_json)
    # p ro
    ore_url = ro["Aggregation"]["@id"]
    p ore_url


    begin
      ore_json = RestClient.get ore_url

      if ro_json.code != 200
        p "ERROR: Invalid URL #{ore_url} -- #{ore_url.code}"
        message = "Invalid URL #{ore_url} -- #{ore_url.code}"
        stage = "Failure"
        # update_status(stage, message, updatestatus_url)
        next
      end

    rescue => e
      p "ERROR: Cannot reach #{ore_url} (#{e})"
      message = "Cannot reach #{ore_url} (#{e})"
      stage = "Failure"
      # update_status(stage, message, updatestatus_url)
      next
    end


    ore = JSON.parse(ore_json)

    # Retrieve the metadata for the item
    id = ore["describes"]["@id"]
    title = ore["describes"]["Title"]
    abstract = ore["describes"]["Abstract"]
    rights = ore["Rights"]
    creator = ore["describes"]["Creator"]
    date = ore["describes"]["Creation Date"]

    p "Abstract: #{abstract}"
    p "Title: #{title}"
    p "Creator: #{creator}"
    p "Right: #{rights}"
    p "date: #{date}"

    begin
      new_directory = "#{title}"
      Dir.mkdir(@config['seaddata']['directory']+new_directory) unless File.exist?(@config['seaddata']['directory']+new_directory)
      orefile = @config['seaddata']['directory'] + "#{new_directory}/#{title}.jsonld"
      File.open(orefile, "wb") do |f|
        f.write(ore_json)
      end
    rescue => e
      p "ERROR: Cannot download file to temp location -- (#{e})"
      message = "Cannot download file to temp location -- (#{e})"
      stage = "Failure"
      # update_status(stage, message, updatestatus_url)
    end

    itemid, itemhandle = create_item(id, title, abstract, creator, rights, date, orefile)

    # Retrieve aggreagated resources metadata
    aggregated_resources = ore["describes"]["aggregates"]
    # p aggregated_resources.class

    aggregated_resources.each do |ar|
      file_url = ar['similarTo']
      title = ar['Title']
      mime = ar['Mimetype']
      date = ar['Date']


      bitstream = @config['seaddata']['directory'] + "#{new_directory}/#{title}"
      File.open(bitstream, "wb") do |saved_file|
        # the following "open" is provided by open-uri
        open(file_url, "rb", :http_basic_authentication=>[@config['seaddata']['email'], @config['seaddata']['password']]) do |read_file|
          saved_file.write(read_file.read)
        end
      end

      File.open(orefile, "wb") do |f|
        f.write(ore_json)
      end

      update_item itemid, bitstream, title, mime, date

    end


    # Return Handle ID to SEAD
    message = @config['dspacedata']['host'] + "handle/#{itemhandle}"
    stage = "Success"
    # update_status(stage, message, updatestatus_url)


  end

end