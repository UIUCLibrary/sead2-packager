#!usr/bin/env ruby

require 'rubygems'
require 'json'
require 'rest-client'
require 'cgi'
require 'open-uri'


def login
  host = 'http://localhost:8080'
  user = 'njkhan505@gmail.com'
  pwd = '123456'
  begin
    response = RestClient.post("#{host}/rest/login", {"email" => "#{user}", "password" => "#{pwd}"}.to_json,
                               {:content_type => 'application/json',
                                :accept => 'application/json'})
    login_token = response.to_str
    puts "Your login token is: #{login_token}"

  rescue => e
    puts "ERROR: #{e}"
  end
end

login

researchobjects = RestClient.get 'http://seadva-test.d2i.indiana.edu/sead-c3pr/api/repositories/ideals/researchobjects'
researchobjects_parsed = JSON.parse(researchobjects)
# p researchobjects_parsed

researchobjects_parsed.each do |researchobject|
  agg_id = "#{researchobject['Aggregation']['Identifier']}"
  stage = "#{researchobject['Status'][0]['stage']}"
  reporter = "#{researchobject['Status'][0]['reporter']}"


  old_item = false
  researchobject['Status'].each do |status|
    old_item = false unless status['stage'] == "Receipt Acknowledged" && status['reporter'] == "SEAD-CP"
  end


  if old_item then
    p "WARNING: Skipping #{agg_id}. Stage = #{stage}, Reporter = #{reporter}"
    next
  else

    agg_id_escaped = CGI.escape(agg_id)
    # p agg_id_escaped
    ro_url = 'http://seadva-test.d2i.indiana.edu/sead-c3pr/api/researchobjects/'+ agg_id_escaped
    # p 'Retreive Research Object from this link: '+ ro_url

    updatestatus_url = "http://seadva-test.d2i.indiana.edu/sead-c3pr/api/researchobjects/#{agg_id_escaped}/status"

    begin
      # postStatus = RestClient.post("#{updatestatus_url}", {"reporter" => "Ideals", "stage" => "Pending"}.to_json, {:content_type => :json, :accept => :json})


    rescue => e
      p "ERROR: Cannot update status at #{updatestatus_url} (#{e})"
      next
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
    # p ore

    # ars = Array.new
    # ars << ore
    # p ars.count

      File.open("/Users/njkhan2/Desktop/test.jsonjd", "wb") do |f|
        f.write(ore.to_json)
      end


    title = ore["describes"]["Title"]
    abstract = ore["describes"]["Abstract"]
    rights = ore["Rights"]
    creator = ore["describes"]["Creator"]
    date = ore["describes"]["Creation Date"]
    getFile = ore["describes"]["aggregates"][0]["similarTo"]
    p "Abstract:  + #{abstract}\n Title: + #{title} \n Creator: + #{creator} \n Right: + #{rights} \n date: + #{date} \n URL for binary file: + #{getFile}"



    cookie_url = 'sead-test.ncsa.illinois.edu'

    jar = HTTP::CookieJar.new
    jar.load('sead.cookie')

    p jar.cookies

    cookie = HTTP::Cookie.cookie_value(jar.cookies(cookie_url))
    p cookie

    begin
      response = RestClient.get(getFile, {:cookies => cookie})

      p response.code

    rescue => e
      p "ERROR: Cannot get file at #{getFile} (#{e})"
      next
    end



  end

end

test_json = '[{"key":"dcterms.modified", "value":"2014-03-24T11:32:03-0400", "language":"en"},{"key":"dcterms.identifier", "value":"http://sead-test/fakeUri/0489a707-d428-4db4-8ce0-1ace548bc653", "language":"en"},{"key":"dcterms.title", "value":"Vortex2 Visualization", "language":"en"},{"key":"dcterms.abstract", "value":"The Vortex2 project (http://www.vortex2.org/home/) supported 100 scientists using over 40 science support vehicles participated in a nomadic effort to understand tornados. For the six weeks from May 1st to June 15th, 2010, scientists went roaming from state-to-state following severe weather conditions. With the help of meteorologists in the field who initiated boundary conditions, LEAD II (https://portal.leadproject.org/gridsphere/gridsphere) delivered six forecasts per day, starting at 7am CDT, creating up to 600 weather images per day. This information was used by the VORTEX2 field team and the command and control center at the University of Oklahoma to determine when and where tornadoes are most likely to occur and to help the storm chasers get to the right place at the right time. VORTEX2 used an unprecedented fleet of cutting edge instruments to literally surround tornadoes and the supercell thunderstorms that form them. An armada of mobile radars, including the Doppler On Wheels (DOW) from the Center for Severe Weather Research (CSWR), SMART-Radars from the University of Oklahoma, the NOXP radar from the National Severe Storms Laboratory (NSSL), radars from the University of Massachusetts, the Office of Naval Research and Texas Tech University (TTU), 12 mobile mesonet instrumented vehicles from NSSL and CSWR, 38 deployable instruments including Sticknets (TTU), Tornado-Pods (CSWR), 4 disdrometers (University of Colorado (CU)), weather balloon launching vans (NSSL, NCAR and SUNY-Oswego), unmanned aircraft (CU), damage survey teams (CSWR, Lyndon State College, NCAR), and photogrammetry teams (Lyndon State Univesity, CSWR and NCAR), and other instruments.", "language":"en"},{"key":"dcterms.publisher", "value":"http://d2i.indiana.edu/", "language":"en"},{"key":"dcterms.rights", "value":"All the data and visualizations are available for download and re-use. Proper attribution to the authors is required.", "language":"en"},{"key":"dcterms.creator", "value":"Quan Zhou", "language":"en"}]'