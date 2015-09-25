#!usr/bin/env ruby

require 'rubygems'
require 'json'
require 'rest-client'
require 'cgi'

ro = RestClient.get 'https://sead-test.ncsa.illinois.edu/seadcp0.91/cp/repositories/Ideals/researchobjects'
parsed = JSON.parse(ro)
# puts parsed

parsed.each do |object|
  stage = "#{object['Status'][0]['stage']}"
  # p stage
  
  if stage == "Receipt Ackowledged" then
    get_id = "#{object['Aggregation']['Identifier']}"
    encodeID = CGI.escape(get_id)
    # p encodeID
    appendTo = 'https://sead-test.ncsa.illinois.edu/seadcp0.91/cp/researchobjects/'+ encodeID
    # p 'Retreive ORE from this link: '+ appendTo

    getORE = RestClient.get appendTo
    parseORE = JSON.parse(getORE)
    id = parseORE["Aggregation"]["@id"]
    # p id
    
    begin
      getMetadata = RestClient.get id
      parseMetadata = JSON.parse(getMetadata)
      # p parseMetadata
      if getMetadata
        puts parseMetadata
        
        updatestatus = "https://sead-test.ncsa.illinois.edu/seadcp0.91/cp/researchobjects/#{encodeID}/status"
        postStatus = RestClient.post("#{updatestatus}", {"reporter" => "Ideals", "stage" => "Pending"}.to_json, {:content_type => :json, :accept => :json})
      else
        continue
      end
    rescue => e
    end
    
    
    
  else
    continue
  end
end