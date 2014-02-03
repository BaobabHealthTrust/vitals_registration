require 'rubygems'
require 'rest-client'

@start_time = DateTime.now
@end_time = nil

def start
  
  birth_reports = BirthReport.all(:select => ["patient_id"])
  maternity_link = "http://localhost:3000/patients/issue_birth_report?"
  
  birth_reports.each do |report|

    details = BirthReportDetails.find_by_patient_id(report.patient_id) #rescue nil
    identifier = Patient.find(report.patient_id).national_id

    if details.blank?
      uri = maternity_link + "identifier=#{identifier}"
      remote_birth_report = JSON.parse(RestClient.get(uri)) rescue {}

      if remote_birth_report["report"].blank?   # i.e maybe birth report was locally created
        puts "Working on birth report for baby with ID = #{report.patient_id}"
        first_relationship = Relationship.find_by_sql(
          ["SELECT date_created FROM relationship WHERE person_a = ? ORDER BY date_created ASC LIMIT 1",
            report.patient_id
          ]
        ).first rescue nil

        unless first_relationship.blank?
          
          date_created = first_relationship.date_created.to_date.to_s + " " + first_relationship.date_created.strftime("%H:%M:%S")
          
          ActiveRecord::Base.connection.execute("INSERT INTO birth_report_details(patient_id, date_created, date_updated)
              VALUES (#{report[:patient_id]}, '#{date_created}', '#{date_created}');"
          )
          
        end
        
        next
        
      end
      
      puts "Working on birth report(remote) for baby with ID = #{report.patient_id}"
      facility = remote_birth_report["facility"]
      remote_birth_report = remote_birth_report["report"]
      
      date_received = remote_birth_report["acknowledged"].to_date.to_s + " " + remote_birth_report["acknowledged"].to_datetime.strftime("%H:%M:%S")
      date_created = remote_birth_report["date_created"].to_date.to_s + " " + remote_birth_report["date_created"].to_datetime.strftime("%H:%M:%S")
      date_updated = remote_birth_report["date_updated"].to_date.to_s + " " + remote_birth_report["date_updated"].to_datetime.strftime("%H:%M:%S")

      ActiveRecord::Base.connection.execute("INSERT INTO birth_report_details(patient_id, date_created, date_received, date_updated, source)
              VALUES (#{report["patient_id"]}, '#{date_created}', '#{date_received}', '#{date_updated}', '#{facility}');"
      )
      
    end

  end
  @end_time = DateTime.now
end

puts "Started at #{@start_time}"
start

puts "Started at #{@start_time}"
puts "Ended at #{@end_time}"
  
