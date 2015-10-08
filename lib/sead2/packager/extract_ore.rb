#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'rest-client'
require 'cgi'
require 'open-uri'
require 'active_support/all'
require 'rdf'
require 'linkeddata'

@host = 'https://seadtest.ideals.illinois.edu'

# Login to DSpace
def login_dspace

  dspaceuser = 'njkhan505@gmail.com'

  pwd = '123456'
  begin
    response = RestClient.post("#{@host}/rest/login", {"email" => "#{dspaceuser}", "password" => "#{pwd}"}.to_json,
                               {:content_type => 'application/json',
                                :accept => 'application/json'})
    @login_token = response.to_str
    puts "Your login token is: #{@login_token}"

  rescue => e
    puts "ERROR: #{e}"
  end
end



# Log in to SEAD
def login_sead
  @host_sead = "https://sead-test.ncsa.illinois.edu/acr/#login/"
  seaduser = 'njkhan2@illinois.edu'
  pwd = '123456'

  begin
    response = RestClient.post("#{@host_sead}", {"email" => "#{seaduser}", "password" => "#{pwd}"}.to_json,
                               {:content_type => 'application/json',
                                :accept => 'application/json'})

    puts response.code

  rescue => e
    puts "ERROR: #{e}"
  end
end


# Creates item and posts ORE for the item
def create_item (title, abstract, creator, rights, date, orefile)

  # Create an item
  puts 'Creating an item.'
  begin
    item = RestClient.post("#{@host}/rest/collections/116/items",{"type" => "item"}.to_json,
                           {:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })
    puts item.to_str
    puts "Response status: #{item.code}"
    getitemid = JSON.parse(item)
    itemid = "#{getitemid["id"]}"
    itemhandle = "#{getitemid["handle"]}"
    puts "Item ID is: #{itemid}"


    # update item metadata
    metadata = [{"key"=>"dc.date", "value"=>"#{date}", "language"=>"en"},{"key"=>"dc.title", "value"=>"#{title}", "language"=>"en"},{"key"=>"dc.description.abstract", "value"=>"#{abstract}", "language"=>"en"},{"key"=>"dc.creator", "value"=>"#{creator}", "language"=>"en"}]

    aggmetadata = RestClient.put("#{@host}/rest/items/#{itemid}/metadata", "#{metadata.to_json}",
                                 {:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })

    p "Response status: #{aggmetadata.code}"


    # post orefile
    postore = RestClient.post("#{@host}/rest/items/#{itemid}/bitstreams?name=#{title.gsub(' ', '_')}.jsonld&description=ORE_file",
                              {
                                  :transfer =>{
                                      :type => 'bitstream'
                                  },
                                  :upload => {
                                      :file => File.new("#{orefile}",'rb'),
                                      :mimeType => 'application/ld+json'
                                  }
                              } ,{:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })
    response_code = "#{postore.code}"
    p postore
    puts "Response status: #{response_code}"

    if "#{response_code}" != "200"
      p "ORE ingestion failed"
    else
      p "Handle is: #{itemhandle}"
    end

    return itemid, itemhandle

  end
end

def update_item(itemid, bitstream, title, mime, date)
  # code here
  postore = RestClient.post("#{@host}/rest/items/#{itemid}/bitstreams?name=#{title.gsub(' ', '_')}",
                            {
                                :transfer =>{
                                    :type => 'bitstream'
                                },
                                :upload => {
                                    :file => File.new("#{bitstream}",'rb')
                                }
                            } ,{:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })
  response_code = "#{postore.code}"
  p postore
  puts "Response status: #{response_code}"
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
researchobjects = RestClient.get 'http://seadva-test.d2i.indiana.edu/sead-c3pr/api/repositories/ideals/researchobjects'
researchobjects_parsed = JSON.parse(researchobjects)

# p researchobjects_parsed

researchobjects_parsed.each do |researchobject|
  agg_id = "#{researchobject['Aggregation']['Identifier']}"


  old_item = false
  researchobject['Status'].each do |status|
    old_item = true unless status['stage'] == "Receipt Acknowledged" && status['reporter'] == "SEAD-CP"
  end


  if old_item then
    p "WARNING: Skipping #{agg_id}. Current status: stage = #{researchobject['Status'].last['stage']}, reporter = #{researchobject['Status'].last['reporter']}"
    next
  else

    agg_id_escaped = CGI.escape(agg_id)
    # p agg_id_escaped
    ro_url = 'http://seadva-test.d2i.indiana.edu/sead-c3pr/api/researchobjects/'+ agg_id_escaped

    # p 'Retreive Research Object from this link: '+ ro_url

    updatestatus_url = "http://seadva-test.d2i.indiana.edu/sead-c3pr/api/researchobjects/#{agg_id_escaped}/status"
    message = "Processing research object"
    stage = "Pending"
    update_status(stage, message, updatestatus_url)

    ro_json = RestClient.get ro_url
    # p ro_json

    if ro_json.code != 200
      p "ERROR: Invalid URL #{ro_url} -- #{ro_json.code}"
    end

    ro = JSON.parse(ro_json)
    # p ro
    ore_url = ro["Aggregation"]["@id"]
    p ore_url


    begin
      ore_json = RestClient.get ore_url

      if ro_json.code != 200
        p "ERROR: Invalid URL #{ore_url} -- #{ore_url.code}"
      end

    rescue => e
      p "ERROR: Cannot reach #{ore_url} (#{e})"
      next
    end


    ore = JSON.parse(ore_json)

    # Retrieve the metadata for the item
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

    orefile = "/Users/njkhan2/Desktop/sead-test/#{title}.jsonld"
    File.open(orefile, "wb") do |f|
      f.write(ore_json)
    end

    itemid, itemhandle = create_item title, abstract, creator, rights, date, orefile

    # Retrieve aggreagated resources metadata
    aggregated_resources = ore["describes"]["aggregates"]
    # p aggregated_resources.class

    aggregated_resources.each do |ar|
      file_url = ar['similarTo']
      title = ar['Title']
      mime = ar['Mimetype']
      date = ar['Date']


      bitstream = "/Users/njkhan2/Desktop/sead-test/#{title}"
      File.open(bitstream, "wb") do |saved_file|
        # the following "open" is provided by open-uri
        open(file_url, "rb", :http_basic_authentication=>['njkhan2@illinois.edu', '123456']) do |read_file|
          saved_file.write(read_file.read)
        end
      end

      File.open(orefile, "wb") do |f|
        f.write(ore_json)
      end

      update_item itemid, bitstream, title, mime, date

    end


    # Return Handle ID to SEAD
    message = "https://seadtest.ideals.illinois.edu/handle/#{itemhandle}"
    stage = "Success"
    update_status(stage, message, updatestatus_url)



  end

end