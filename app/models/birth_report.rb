class BirthReport < ActiveRecord::Base
	set_table_name "birth_report"
	set_primary_key "patient_id"
  include Openmrs

  belongs_to :person, :conditions => {:voided => 0}

  def self.cohort_data(links_ids = {}, start_date = Date.today, end_date=Date.today)

    @center = "SELECT value FROM person_attribute WHERE person_id = prsn.person_id AND person_attribute_type_id =
                (SELECT person_attribute_type_id FROM person_attribute_type WHERE name = 'health center' LIMIT 1) LIMIT 1"

    @hospital_date = "SELECT value FROM person_attribute WHERE person_id = prsn.person_id AND person_attribute_type_id =
                (SELECT person_attribute_type_id FROM person_attribute_type WHERE name = 'hospital date' LIMIT 1) LIMIT 1"
                
    @result = BirthReport.find_by_sql(["SELECT br.patient_id AS pid, 'Current Site' AS source, prsn.gender AS sex, (#{@hospital_date}) AS hospital_date,
                                          COALESCE((#{@center}), 'Unknown') AS health_center, COALESCE(DATE(br.date_of_birth), '') AS dob, COALESCE(br.district_of_birth, 'Unknown') AS birth_district
                                        FROM birth_report br
                                              INNER JOIN person prsn ON br.patient_id = prsn.person_id AND prsn.voided = 0
                                              WHERE DATE(prsn.date_created) BETWEEN ? AND ?", start_date.to_date, end_date.to_date]
    ).collect{|report|
      source = links_ids.invert[links_ids.invert.keys.delete_if{|key| !key.include?(report.pid.to_i)}[0]]
      report.source = source if source.present?
      report
    }

  end

  def self.filter_fields(data)
    #data is a hash of active record objects
    result = {}
    
    (data.first.attributes.keys || []).each do |key|
      next if key.match(/pid|hospital\_date|dob/)
      result[key.titleize] = data.inject({}) { |h, obj| h.has_key?(obj[key])? (h[obj[key]] << [obj.pid.to_i, obj.sex]) : ( h[obj[key]] = [[obj.pid.to_i, obj.sex]]); h }

      result[key.titleize].keys.each {|ky|

        males = []
        females = []
    
        result[key.titleize][ky].each {|val|
          val[1].match(/F/i) ? (females << val[0]) : (males << val[0])
        }     
        
        result[key.titleize][ky] = [males, females]

      }
  
    end rescue {}

    result
   
  end
  
end
