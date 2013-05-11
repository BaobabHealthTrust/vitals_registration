class ReportsController < ActionController::Base
  
  def select
=begin
    @nationalities = []
    @babies_map = {}

    BirthReport.find(:all).collect{|b|
      @nationalities << b.nationality_mother
      @nationalities << b.nationality_father
    }

    @nationalities.uniq!
=end
    
  end

  def report
    @parameters = ""

    if !params["start_date"].blank? && !params["end_date"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&start_date=#{params["start_date"]}&end_date=#{params["end_date"]}"
      else
        @parameters = "start_date=#{params["start_date"]}&end_date=#{params["end_date"]}"
      end
    end

    if !params["Hospital"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&facility=#{params["Hospital"]}"
      else
        @parameters = "facility=#{params["Hospital"]}"
      end
    end

    if !params["current_district"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&current_district=#{params["current_district"]}"
      else
        @parameters = "current_district=#{params["current_district"]}"
      end
    end

    if !params["home_district"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&home_district=#{params["home_district"]}"
      else
        @parameters = "home_district=#{params["home_district"]}"
      end
    end

    if !params["birth_district"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&birth_district=#{params["birth_district"]}"
      else
        @parameters = "birth_district=#{params["birth_district"]}"
      end
    end

    if !params["nationality"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&nationality=#{params["nationality"]}"
      else
        @parameters = "nationality=#{params["nationality"]}"
      end
    end
    if !@parameters.blank?
      @parameters = "?" + @parameters
    end
  end

  def report_printable
    @babies = []

    if params[:select_by] && params[:select_by].downcase == "nationality"

      @groups = []
      @header = "Nationality"
      @babies_map = {}
      @babies = BirthReport.find(:all)      
      
      @babies.each do |baby|
        
        mother_nationality = (baby.nationality_mother.blank? || baby.nationality_mother.to_s.strip == "")? "Unknown Nationality" : baby.nationality_mother
        father_nationality = (baby.nationality_father.blank? || baby.nationality_father.to_s.strip == "" )? "Unknown Nationality" : baby.nationality_father
        
              
        if mother_nationality.to_s.downcase.strip == father_nationality.to_s.downcase.strip
          
          @babies_map["#{mother_nationality}"] = [] if  @babies_map["#{mother_nationality}"].class.to_s.downcase != "array"
          @babies_map["#{mother_nationality}"] << baby.patient_id if !@babies_map["#{mother_nationality}"].include?(baby.patient_id)
          
        else mother_nationality.to_s.downcase != father_nationality.to_s.downcase
          
          if  @babies_map["Dual Nationality"].class.to_s.downcase != "array"
            @babies_map["Dual Nationality"] = []           
          end          
          @babies_map["Dual Nationality"]<< baby.patient_id if ![mother_nationality, father_nationality].include?("Unknown Nationality")
          next if [mother_nationality, father_nationality].include?("Unknown Nationality")
          #nationality = (mother_nationality != "Unknown Nationality")? mother_nationality : father_nationality
          @babies_map["#{mother_nationality}"] = [] if  @babies_map["#{mother_nationality}"].class.to_s.downcase != "array"
          @babies_map["#{mother_nationality}"] << baby.patient_id if !@babies_map["#{mother_nationality}"].include?(baby.patient_id)

          @babies_map["#{father_nationality}"] = [] if  @babies_map["#{father_nationality}"].class.to_s.downcase != "array"
          @babies_map["#{father_nationality}"] << baby.patient_id if !@babies_map["#{father_nationality}"].include?(baby.patient_id)
        end
        
        #temp = @babies_map["#{father_nationality}"].concat(@babies_map["#{mother_nationality}"])
        #@babies_map["Unknown Nationality"] = @babies_map["Unknown Nationality"] -  temp
        
      end
      #raise @babies_map.to_yaml
      @groups = @babies_map.keys
      #raise @babies_map.to_yaml

      @groups = @groups.insert(0, @groups.delete_at(@groups.index("Unknown Nationality"))) rescue @groups
                    
      @groups = @groups.insert(0, @groups.delete_at(@groups.index("Dual Nationality"))) rescue @groups
      
      # raise @babies_map.to_yaml
    end

    if params[:select_by] && params[:select_by].downcase == "district of birth"
      @groups = []
      @header = "District Of Birth"
      @babies_map = {}
      @babies = BirthReport.find(:all)

      @babies.each do |baby|
        district = baby.district_of_birth.blank?? "Unknown District Of Birth" : baby.district_of_birth
        
        @babies_map["#{district}"] = [] if @babies_map["#{district}"].class.to_s.downcase != "array"
        @babies_map["#{district}"] << baby.patient_id if !@babies_map["#{district}"].include?(baby.patient_id)
      end
      @groups = @babies_map.keys
    end

    if params[:select_by] && params[:select_by].downcase == "health facility"
      @groups = []
      @header = "Health Facility"
      @babies_map = {}
      @babies = BirthReport.find(:all)
      prov_facility_attr = PersonAttributeType.find_by_name("Health Center").id
      
      @babies.each do |baby|
        facility = PersonAttribute.find(:first, :order => ["date_created DESC"],
          :conditions => ["person_attribute_type_id = ? AND person_id = ?",
            prov_facility_attr, baby.patient_id]).value rescue nil
        
        facility = facility.blank?? "Unknown Health Facility" : facility

        @babies_map["#{facility}"] = [] if @babies_map["#{facility}"].class.to_s.downcase != "array"
        @babies_map["#{facility}"] << baby.patient_id if !@babies_map["#{facility}"].include?(baby.patient_id)
      end
      @groups = @babies_map.keys
    end
    
   
    if params[:select_by] && params[:select_by].downcase == "date of birth" && !params["start_date"].blank? && !params["end_date"].blank?
      @babies = (BirthReport.find(:all, :conditions => ["DATE(date_of_birth) >= ? AND DATE(date_of_birth) <= ?",
            params["start_date"], params["end_date"]]) rescue []).uniq.collect{|br| br.patient_id if !br.blank?} rescue []           
    end  
    
    render :layout => false
  end

  def debugger
    patients = params[:ids].split(",")
    @babies = BirthReport.find(:all, :conditions => ["patient_id IN (?)", patients])
     render :layout => false
  end

  def print_note
    # raise request.remote_ip.to_yaml
    @parameters = ""

    if !params["start_date"].blank? && !params["end_date"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&start_date=#{params["start_date"]}&end_date=#{params["end_date"]}"
      else
        @parameters = "start_date=#{params["start_date"]}&end_date=#{params["end_date"]}"
      end
    end

    if !params["current_district"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&current_district=#{params["current_district"]}"
      else
        @parameters = "current_district=#{params["current_district"]}"
      end
    end

    if !params["home_district"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&home_district=#{params["home_district"]}"
      else
        @parameters = "home_district=#{params["home_district"]}"
      end
    end

    if !params["birth_district"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&birth_district=#{params["birth_district"]}"
      else
        @parameters = "birth_district=#{params["birth_district"]}"
      end
    end

    if !params["nationality"].blank?
      if !@parameters.blank?
        @parameters = @parameters + "&nationality=#{params["nationality"]}"
      else
        @parameters = "nationality=#{params["nationality"]}"
      end
    end

    if !@parameters.blank?
      @parameters = "?" + @parameters
    end

    location = request.remote_ip rescue ""
    
    current_printer = ""

    wards = GlobalProperty.find_by_property("facility.ward.printers").property_value.split(",") rescue []

    printers = wards.each{|ward|
      current_printer = ward.split(":")[1] if ward.split(":")[0].upcase == location
    } rescue []

    t1 = Thread.new{

      Kernel.system "wkhtmltopdf -s A4 http://" +
        request.env["HTTP_HOST"] + "\"/reports/report_printable#{@parameters}" +
        "\" /tmp/output-" + session[:user_id].to_s + ".pdf \n"
    }

    t2 = Thread.new{
      sleep(5)
      Kernel.system "lp #{(!current_printer.blank? ? '-d ' + current_printer.to_s : "")} /tmp/output-" +
        session[:user_id].to_s + ".pdf\n"
    }

    t3 = Thread.new{
      sleep(10)
      Kernel.system "rm /tmp/output-" + session[:user_id].to_s + ".pdf\n"
    }

    redirect_to "/reports/select" and return
  end

end
