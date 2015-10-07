#!usr/bin/env ruby

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
def login

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

login


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

    begin
      postStatus = RestClient.post("#{updatestatus_url}", {"reporter" => "ideals", "stage" => "Pending", "message" => "Processing research object"}.to_json, {:content_type => :json, :accept => :json})


    rescue => e
      p "WARNING: Cannot update status at #{updatestatus_url} (#{e})"
      # next
    end


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

    # Retrieve the metadata
    @title = ore["describes"]["Title"]
    @abstract = ore["describes"]["Abstract"]
    @rights = ore["Rights"]
    @creator = ore["describes"]["Creator"]
    @date = ore["describes"]["Creation Date"]

    p "Abstract: #{@abstract}"
    p "Title: #{@title}"
    p "Creator: #{@creator}"
    p "Right: #{@rights}"
    p "date: #{@date}"


    # Retrieve aggreagated resources metadata
    getBitstream = ore["describes"]["aggregates"]
    # p getBitstream.class

    files = getBitstream.map{|h| h["similarTo"]}
    arTitles = getBitstream.map{|h| h["Title"]}
    p files
    p arTitles


    # Converts json-ld to xml
    # graph = RDF::Graph.load(ore_url , format: :jsonld)
    # @orefile = "/Users/njkhan2/Desktop/sead-test/#{@title}.xml"
    # File.open(@orefile, "wb") do |f|
    #   f.write(graph.dump :rdfxml, standard_prefixes: true)
    # end

    @orefile = "/Users/njkhan2/Desktop/sead-test/#{@title}.jsonld"
    File.open(@orefile, "wb") do |f|
      f.write(ore_url)
    end


    # Creates item and posts ORE for the item
    def createItem

      # Create an item
      puts 'Creating an item.'
      begin
        item = RestClient.post("#{@host}/rest/collections/116/items",{"type" => "item"}.to_json,
                               {:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })
        puts item.to_str
        puts "Response status: #{item.code}"
        getitemid = JSON.parse(item)
        itemid = "#{getitemid["id"]}"
        @itemhandle = "#{getitemid["handle"]}"
        puts "Item ID is: #{itemid}"


      # update item metadata
        metadata = [{"key"=>"dc.date", "value"=>"#{@date}", "language"=>"en"},{"key"=>"dc.title", "value"=>"#{@title}", "language"=>"en"},{"key"=>"dc.description.abstract", "value"=>"#{@abstract}", "language"=>"en"},{"key"=>"dc.creator", "value"=>"#{@creator}", "language"=>"en"}]

        aggmetadata = RestClient.put("#{@host}/rest/items/#{itemid}/metadata", "#{metadata.to_json}",
                                  {:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })

        p "Response status: #{aggmetadata.code}"


      # post orefile
        postore = RestClient.post("#{@host}/rest/items/#{itemid}/bitstreams?name=#{@title.gsub(' ', '_')}.jsonld&description=ORE_file",
                                    {
                                        :transfer =>{
                                            :type => 'bitstream'
                                        },
                                        :upload => {
                                            :file => File.new("#{@orefile}",'rb')
                                        }
                                    } ,{:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })
        response_code = "#{postore.code}"
        p postore
        puts "Response status: #{response_code}"

        if "#{response_code}" != "200"
          p "ORE ingestion failed"
        else
          p "Handle is: #{@itemhandle}"
        end


      # Get and post ar bitstreams
        firstBitstream = ore["describes"]["aggregates"][0]["similarTo"]
        getFile = RestClient.get firstBitstream

      # update bitstream metadata
      #   getoreid = JSON.parse(postore)
      #   oreid = "#{getoreid["id"]}"
      #   p "Bitstream id is: #{oreid}"
      #
      #   # ore_metadata = [{"key"=>"format", "value"=>"JSON-LD", "language"=>"en"},{"key"=>"mimeType", "value"=>"application/ld+json", "language"=>"en"}]
      #   ore_metadata = [{"mimeType"=>"application/ld+json"}]
      #   updatemetadata = RestClient.put("#{@host}/rest/bitstreams/#{oreid}", "#{ore_metadata.to_json}",
      #                                {:content_type => 'application/json', :accept => 'application/json', :rest_dspace_token => "#{@login_token}" })
      #   p updatemetadata
      #   p "Response status: #{updatemetadata.code}"

      end
    end

    createItem


    # Return Handle ID to SEAD
    begin
      returnHandle = RestClient.post("#{updatestatus_url}", {"reporter" => "ideals", "stage" => "Success", "message" => "https://seadtest.ideals.illinois.edu/handle/#{@itemhandle}"}.to_json, {:content_type => :json, :accept => :json})


    rescue => e
      p "WARNING: Cannot update status at #{updatestatus_url} (#{e})"
      # next
    end

    # cookie_url = 'sead-test.ncsa.illinois.edu'
    #
    # jar = HTTP::CookieJar.new
    # jar.load('sead.cookie')
    #
    # p jar.cookies
    #
    # cookie = HTTP::Cookie.cookie_value(jar.cookies(cookie_url))
    # p cookie
    #
    # begin
    #   response = RestClient.get(getFile, {:cookies => cookie})
    #
    #   p response.code
    #
    # rescue => e
    #   p "ERROR: Cannot get file at #{getBitstream} (#{e})"
    #   next
    # end



  end

end