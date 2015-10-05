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

  user = 'njkhan505@gmail.com'
  pwd = '123456'
  begin
    response = RestClient.post("#{@host}/rest/login", {"email" => "#{user}", "password" => "#{pwd}"}.to_json,
                               {:content_type => 'application/json',
                                :accept => 'application/json'})
    @login_token = response.to_str
    puts "Your login token is: #{@login_token}"

  rescue => e
    puts "ERROR: #{e}"
  end
end

login


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
      # p "ERROR: Cannot reach #{ore_url} (#{e})"
      next
    end


    ore = JSON.parse(ore_json)

    # Retrieve the metadata
    @title = ore["describes"]["Title"]
    @abstract = ore["describes"]["Abstract"]
    @rights = ore["Rights"]
    @creator = ore["describes"]["Creator"]
    @date = ore["describes"]["Creation Date"]
    getBitstream = ore["describes"]["aggregates"][0]["similarTo"]
    p "Abstract: #{@abstract}"
    p "Title: #{@title}"
    p "Creator: #{@creator}"
    p "Right: #{@rights}"
    p "date: #{@date}"
    p "URL for binary file: + #{getBitstream}"


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
        postore = RestClient.post("#{@host}/rest/items/#{itemid}/bitstreams?name=#{@title}.jsonld&description=ORE_file",
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


test_json = '[{"key":"dcterms.modified", "value":"2014-03-24T11:32:03-0400", "language":"en"},{"key":"dcterms.identifier", "value":"http://sead-test/fakeUri/0489a707-d428-4db4-8ce0-1ace548bc653", "language":"en"},{"key":"dcterms.title", "value":"Vortex2 Visualization", "language":"en"},{"key":"dcterms.abstract", "value":"The Vortex2 project (http://www.vortex2.org/home/) supported 100 scientists using over 40 science support vehicles participated in a nomadic effort to understand tornados. For the six weeks from May 1st to June 15th, 2010, scientists went roaming from state-to-state following severe weather conditions. With the help of meteorologists in the field who initiated boundary conditions, LEAD II (https://portal.leadproject.org/gridsphere/gridsphere) delivered six forecasts per day, starting at 7am CDT, creating up to 600 weather images per day. This information was used by the VORTEX2 field team and the command and control center at the University of Oklahoma to determine when and where tornadoes are most likely to occur and to help the storm chasers get to the right place at the right time. VORTEX2 used an unprecedented fleet of cutting edge instruments to literally surround tornadoes and the supercell thunderstorms that form them. An armada of mobile radars, including the Doppler On Wheels (DOW) from the Center for Severe Weather Research (CSWR), SMART-Radars from the University of Oklahoma, the NOXP radar from the National Severe Storms Laboratory (NSSL), radars from the University of Massachusetts, the Office of Naval Research and Texas Tech University (TTU), 12 mobile mesonet instrumented vehicles from NSSL and CSWR, 38 deployable instruments including Sticknets (TTU), Tornado-Pods (CSWR), 4 disdrometers (University of Colorado (CU)), weather balloon launching vans (NSSL, NCAR and SUNY-Oswego), unmanned aircraft (CU), damage survey teams (CSWR, Lyndon State College, NCAR), and photogrammetry teams (Lyndon State Univesity, CSWR and NCAR), and other instruments.", "language":"en"},{"key":"dcterms.publisher", "value":"http://d2i.indiana.edu/", "language":"en"},{"key":"dcterms.rights", "value":"All the data and visualizations are available for download and re-use. Proper attribution to the authors is required.", "language":"en"},{"key":"dcterms.creator", "value":"Quan Zhou", "language":"en"}]'