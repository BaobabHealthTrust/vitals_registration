require 'rubygems'
require 'fastercsv'
districts = {}
def start
  files = `ls public/districts/`.gsub("\n",",")[0..-2].split(",")
  districts = {}
  count = 0
  tradition_authority = {}
  ta = ''

  files.each do |file_name|
    csv_file =  FasterCSV.read("public/districts/#{file_name}")
    ta = ''

    (csv_file || []).each do |line|
      village = line[0].titleize rescue nil
      code = line[1].to_i rescue 0

      
      #village = village.match(/([a-zA-Z]+)/)[0] rescue village
    
      village = "" + village[0 .. 3].sub(/\d+/, "") + village[4 .. village.size] rescue village
      
 			next if village.blank?
 			
      if village.squish[0..2].match(/TA /i)
        ta = village.upcase.gsub("TA ", "").squish.titleize
        tradition_authority[ta] = []
        next
      end
   
      next if code < 1 or ta.blank?
      #next if tradition_authority[ta].blank?

      if not village.blank? 
        tradition_authority[ta] << village
        tradition_authority[ta] = tradition_authority[ta].uniq
        count+=1
      end
    end
 
    districts[file_name.split(".xls")[0].titleize] = tradition_authority
    puts "District name::::: #{file_name.split(".xls")[0].titleize} ... #{count}"
    tradition_authority = {}

  end
  
  import(districts)

end

def import(data)
  district_names = data.keys.sort rescue []
  
  (district_names  || []).each do |d_name|
  
    next if (d_name.to_s.length < 4 rescue true) || district_id(d_name).blank?
    ta_names = data["#{d_name}"].keys rescue []

    (ta_names  || []).each do |t_name|
          
      next if t_name.blank?
      ta_villages = data["#{d_name}"]["#{t_name}"]
          
      (ta_villages || []).each do |village|

        district_of_interest = district_id(d_name.strip) rescue nil
        
        next if district_of_interest.blank? || village.blank?

        #Add missing ta
        if ta_id(t_name, district_of_interest).blank?
          write_ta(t_name.strip, district_of_interest)         
          puts "Added TA #{d_name} => #{t_name}"
        end
        
        tr_authority_id = ta_id(t_name.strip, district_of_interest) rescue nil

        next if tr_authority_id.blank? || (village_id(village, tr_authority_id).present? )

        #Add missing village
        if village_id(village.strip, tr_authority_id).blank?
          write_village(village.strip, tr_authority_id)
          puts "Added Village  #{d_name} => #{t_name} => #{village}"
        end
      end

    end

  end

end

def self.district_id(ds)

  District.find_by_name(ds).district_id rescue nil

end

def self.ta_id(ta, district)
	
	TraditionalAuthority.find_by_sql("SELECT * FROM traditional_authority
  WHERE district_id = #{district} 	AND (name = '#{ta}' OR name REGEXP  ' #{ta}')").first  rescue nil

end

def self.village_id(vg, ta)

  Village.find_by_name_and_traditional_authority_id(vg, ta).village_id rescue nil

end

def self.write_district(ds, region)

  usr = User.find_by_username("admin").user_id

  district_id = district_id(ds)
  district_full = District.find(district_id) rescue nil

  if district_full.blank?
    District.create(:name => ds.strip,
      :region_id => region,
      :date_created => Date.today,
      :creator => usr)
  else
    district_full.update_attributes(:name => ds.strip,
      :region_id => region,
      :creator => usr)
  end

end

def self.write_ta(ta, district)
  usr = User.find_by_username("admin").user_id

  ta_id = ta_id(ta, district)
  ta_full = TraditionalAuthority.find(ta_id) rescue nil

  if ta_full.blank?
    TraditionalAuthority.create(:name => ta.strip,
      :district_id => district,
      :date_created => Date.today,
      :creator => usr)
  else
    ta_full.update_attributes(:name => ta.strip,
      :district_id => district,
      :creator => usr)
  end
end

def self.write_village(vg, ta)
  usr = User.find_by_username("admin").user_id

  vg_id = village_id(vg, ta)
  vg_full = Village.find(vg_id) rescue nil

  if vg_full.blank?
    Village.create(:name => vg.strip,
      :traditional_authority_id => ta,
      :date_created => Date.today,
      :creator => usr)
  else
    vg_full.update_attributes(:name => vg,
      :traditional_authority_id => ta,
      :creator => usr)
  end
end


start
  
