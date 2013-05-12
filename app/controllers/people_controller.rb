class PeopleController < GenericPeopleController
   
  def create
    
    if params[:cat] && params[:cat].downcase == "mother"
      params["gender"] = "F"
      params["person"]["gender"] = "F"
    elsif params[:cat] && params[:cat].downcase == "father"
      params["gender"] = "M"
      params["person"]["gender"] = "M"
    end

    serial_number_check = PatientIdentifier.find(:all, :conditions => ["identifier = ? AND identifier_type = ?",
        params["person"]["patient"]["identifiers"]["serial number"], PatientIdentifierType.find_by_name("Serial Number").id]) rescue [] if params[:cat].downcase == "baby" && params["person"]["patient"]["identifiers"]["serial number"]

    redirect_to "/patients/no_serial_number?serial_number=#{params["person"]["patient"]["identifiers"]["serial number"]}" and return if serial_number_check && serial_number_check.length > 0
   
    hiv_session = false
    if current_program_location == "HIV program"
      hiv_session = true
    end   
	
    if !params[:identifier].empty? && params[:cat] == "baby"
      if params[:identifier].length == 6
        person = PatientService.create_from_form(params[:person])
        if !person.nil?
          patient_identifier = PatientIdentifier.new
          patient_identifier.type = PatientIdentifierType.find_by_name("National id")
          patient_identifier.identifier = params[:identifier]
          patient_identifier.patient = person.patient
          patient_identifier.save!
        end
      elsif params[:identifier] && create_from_dde_server
        person = ANCService.create_patient_from_dde(params) rescue nil
        if !person.nil?
          old_identifier = PatientIdentifier.new
          old_identifier.type = PatientIdentifierType.find_by_name("Old Identification Number")
          old_identifier.identifier = params[:identifier]
          old_identifier.patient = person.patient
          old_identifier.save!
        end
      else
        redirect_to "/clinic" and return
      end
				
      if params[:encounter] && !person.blank?
        encounter = Encounter.new(params[:encounter])
	   		encounter.patient_id = person.id
        encounter.encounter_datetime = session[:datetime] unless session[:datetime].blank?
        encounter.save
      end

      #print_and_redirect("/patients/national_id_label?patient_id=#{person.id}", "/patients/show?patient_id=#{person.id}?cat=#{params[:cat]}") and return if !person.nil?

      redirect_to "/patients/show?patient_id=#{person.id}?cat=#{params[:cat]}" and return if !person.nil?
    end
    person = ANCService.create_patient_from_dde(params) if create_from_dde_server
    if params[:cat] == "baby"
      redirect_to "/patients/show?patient_id=#{person.id}?cat=#{params[:cat]}" and return if !person.nil?
    else
      if !params[:cat].nil? && !params[:patient_id].nil?
        redirect_to "/relationships/new?patient_id=#{params[:patient_id]}&relation=#{person.id}&cat=#{params[:cat]}" and return if !person.nil?
      else
        redirect_to next_task(person.patient) and return if !person.nil?
      end
    end
    # raise person.to_yaml
    
    unless person.blank?

      encounter = Encounter.new(params[:encounter])
      encounter.patient_id = person.id
      encounter.encounter_datetime = session[:datetime] unless session[:datetime].blank?
      encounter.save rescue nil
     
      redirect_to next_task(person.patient) and return
      
    end

    success = false
    Person.session_datetime = session[:datetime].to_date rescue Date.today
    
    #for now BART2 will use BART1 for patient/person creation until we upgrade BART1 to 2
    #if GlobalProperty.find_by_property('create.from.remote') and property_value == 'yes'
    #then we create person from remote machine
    if create_from_remote
      person_from_remote = PatientService.create_remote_person(params)
      person = PatientService.create_from_form(person_from_remote["person"]) unless person_from_remote.blank?

      if !person.blank?
        success = true
        person.patient.remote_national_id
      end
    else
      success = true
      person = PatientService.create_from_form(params[:person])
    end

    encounter = Encounter.new(params[:encounter])
    encounter.patient_id = person.id
    encounter.encounter_datetime = session[:datetime] unless session[:datetime].blank?
    encounter.save   

    if params[:person][:patient] && success
      PatientService.patient_national_id_label(person.patient)
      # unless (params[:relation].blank?)
      #  redirect_to search_complete_url(person.id, params[:relation]) and return
      if !params[:cat].nil? && !params[:patient_id].nil?        
        redirect_to "/relationships/new?patient_id=#{params[:patient_id]}&relation=#{person.id
            }&cat=#{params[:cat]}" and return
      else

        # print_and_redirect("/patients/national_id_label?patient_id=#{person.id}", next_task(person.patient))

        redirect_to next_task(person.patient) and return
        
      end
    else
      # Does this ever get hit?
      redirect_to :action => "index"
    end
  end

  def create_batch
    @initial_numbers = SerialNumber.all.size

    if ((!params[:start_serial_number].blank? rescue false) && (!params[:end_serial_number].blank? rescue false) &&
          (params[:start_serial_number].to_i < params[:end_serial_number].to_i) rescue false)
      (params[:start_serial_number]..params[:end_serial_number]).each do |number|
        snum = SerialNumber.new()
        snum.serial_number = number
        snum.creator = params[:user_id]
        snum.save if (SerialNumber.find(number).nil? rescue true)
      end
      @created_numbers = SerialNumber.all.size - @initial_numbers
    else
    end
    redirect_to "/clinic/?user_id=#{params[:user_id]}"
  end

  def search
    #synthesize gender values using :cat
    if params[:cat] && params[:cat].downcase == "mother"
      params[:gender] = "F"
    elsif params[:cat] && params[:cat].downcase == "father"
      params[:gender] = "M"
    end
    found_person = nil
    if params[:identifier]
      pdata = PatientService.search_by_identifier(params[:identifier])
      local_results = pdata ? pdata : []
	
      if (pdata.nil?) && create_from_dde_server
        if ["", "baby"].include?(params[:cat]) || !params[:cat]
          params[:cancel_show] = params[:cancel_show]? params[:cancel_show] : "/"
          params[:cancel_destination] = params[:cancel_destination]? params[:cancel_destination] : "/"
        else
          params[:cancel_show] = params[:cancel_show]? params[:cancel_show] : "/patients/show/#{params[:patient_id]}"
          params[:cancel_destination] = params[:cancel_destination]? params[:cancel_destination] : "/patients/show/#{params[:patient_id]}"
        end
        #redirect_to :controller => :clinic, :action => :link_error, :link => dde_server
        redirect_to "/clinic/link_error?cancel_show=#{params[:cancel_show]}&cancel_destination=#{params[:cancel_destination]}" and return
      end
      if local_results.length > 1
        redirect_to :action => 'duplicates' ,:search_params => params
        return			
				#@people = PatientService.person_search(params)
      elsif local_results.length == 1
        if create_from_dde_server
          dde_server = CoreService.get_global_property_value("dde_server_ip") rescue ""
          dde_server_username = CoreService.get_global_property_value("dde_server_username") rescue ""
          dde_server_password = CoreService.get_global_property_value("dde_server_password") rescue ""
          uri = "http://#{dde_server_username}:#{dde_server_password}@#{dde_server}/people/find.json"
          uri += "?value=#{params[:identifier]}"
          output = RestClient.get(uri)
          p = JSON.parse(output)
          if p.count > 1
            redirect_to :action => 'duplicates' ,:search_params => params
            return
          end
        end
        found_person = local_results.first
			else
				# TODO - figure out how to write a test for this
				# This is sloppy - creating something as the result of a GET
				if create_from_remote        
					found_person_data = PatientService.find_remote_person_by_identifier(params[:identifier])
					found_person = PatientService.create_from_form(found_person_data['person']) unless found_person_data.nil?
				end
			end     

      if found_person
=begin
        patient = DDEService::Patient.new(found_person.patient)

        patient.check_old_national_id(params[:identifier])
=end

        if params[:cat] && params[:cat] != "baby" && params[:patient_id]
          redirect_to "/relationships/new?patient_id=#{params[:patient_id]}&relation=#{found_person.id
            }&cat=#{params[:cat]}" and return
        else
          
          redirect_to next_task(found_person.patient) and return
          
          # redirect_to :action => 'confirm', :found_person_id => found_person.id, :relation => params[:relation] and return
        end
      end
    end
		
    @relation = params[:relation]
		@people = PatientService.person_search(params)
    #raise PatientService.search_from_remote(params).to_yaml
    @search_results = {}
    @patients = []
    result_set = PatientService.search_from_remote(params) rescue nil
    
    if result_set.nil?
      if ["", "baby"].include?(params[:cat]) || !params[:cat]
        params[:cancel_show] = params[:cancel_show]? params[:cancel_show] : "/"
        params[:cancel_destination] = params[:cancel_destination]? params[:cancel_destination] : "/"
      else
        params[:cancel_show] = params[:cancel_show]? params[:cancel_show] : "/patients/show/#{params[:patient_id]}"
        params[:cancel_destination] = params[:cancel_destination]? params[:cancel_destination] : "/patients/show/#{params[:patient_id]}"
      end
      #redirect_to :controller => :clinic, :action => :link_error, :link => dde_server
      redirect_to "/clinic/link_error?cancel_show=#{params[:cancel_show]}&cancel_destination=#{params[:cancel_destination]}" and return
    end
    (result_set || []).each do |data|
	  	national_id = data["person"]["data"]["patient"]["identifiers"]["National id"] rescue nil
      national_id = data["person"]["value"] if national_id.blank? rescue nil
      national_id = data["npid"]["value"] if national_id.blank? rescue nil
      national_id = data["person"]["data"]["patient"]["identifiers"]["old_identification_number"] if national_id.blank? rescue nil

      next if national_id.blank?
      results = PersonSearch.new(national_id)
      results.national_id = national_id
      results.current_residence =data["person"]["data"]["addresses"]["city_village"]
      results.person_id = 0
      results.home_district = data["person"]["data"]["addresses"]["address2"]
      results.traditional_authority =  data["person"]["data"]["addresses"]["county_district"]
      results.name = data["person"]["data"]["names"]["given_name"] + " " + data["person"]["data"]["names"]["family_name"]
      gender = data["person"]["data"]["gender"]
      results.occupation = data["person"]["data"]["occupation"]
      results.sex = (gender == 'M' ? 'Male' : 'Female')
      results.birthdate_estimated = (data["person"]["data"]["birthdate_estimated"]).to_i
      results.birth_date = birthdate_formatted((data["person"]["data"]["birthdate"]).to_date , results.birthdate_estimated)
      results.birthdate = (data["person"]["data"]["birthdate"]).to_date
      results.age = cul_age(results.birthdate.to_date , results.birthdate_estimated)
      @search_results[results.national_id] = results
    end if create_from_dde_server 


		(@people || []).each do | person |
			patient = PatientService.get_patient(person) rescue nil
      next if patient.blank?
      results = PersonSearch.new(patient.national_id || patient.patient_id)
      results.national_id = patient.national_id
      results.birth_date = patient.birth_date
      results.current_residence = patient.current_residence
      results.guardian = patient.guardian
      results.person_id = patient.person_id
      results.home_district = patient.home_district
      results.current_district = patient.current_district
      results.traditional_authority = patient.traditional_authority
      results.mothers_surname = patient.mothers_surname
      results.dead = patient.dead
      results.arv_number = patient.arv_number
      results.eid_number = patient.eid_number
      results.pre_art_number = patient.pre_art_number
      results.name = patient.name
      results.sex = patient.sex
      results.age = patient.age
      @search_results.delete_if{|x,y| x == results.national_id }
      @patients << results
		end
    
		(@search_results || {}).each do |npid , data |
      @patients << data
    end
	end

	# This method is just to allow the select box to submit, we could probably do this better
  def select
  
    if params[:person][:id] != '0' && (Person.find(params[:person][:id]).dead == 1 rescue false)

			redirect_to :controller => :patients, :action => :show, :id => params[:person]
		else
			redirect_to search_complete_url(params[:person][:id], params[:relation], 
        params[:cat]) and return if params[:person][:id] != "0" && params[:cat] == "baby"
      
      related_person = PatientService.search_by_identifier(params[:identifier]).first.patient rescue nil
      params[:person][:id] = related_person.id if related_person
     
      redirect_to "/relationships/new?patient_id=#{params[:patient_id]}&relation=#{params[:person][:id]
            }&cat=#{params[:cat]}" and return if (!params[:person][:id].blank? && !(params[:person][:id] == '0')) and
        (params[:cat] and params[:cat] != "baby")
      
      if params[:cat] and params[:cat] == "baby"
        redirect_to :action => :new_baby,
          :gender => params[:gender],
          :given_name => params[:given_name],
          :family_name => params[:family_name],
          :family_name2 => params[:family_name2],
          :address2 => params[:address2], 
          :identifier => params[:identifier],
          :relation => params[:relation]
      else
        redirect_to :action => :new, :gender => params[:gender], 
          :given_name => params[:given_name],
          :family_name => params[:family_name],
          :family_name2 => params[:family_name2],
          :address2 => params[:address2],
          :identifier => params[:identifier],
          :relation => params[:relation],
          :patient_id => params[:patient_id],
          :cat => params[:cat]
      end
		end
	end

  def confirm
    redirect_to "/patients/show/#{params[:patient_id]}?patient_id=#{params[:patient_id]}&cat=#{params[:cat]}" and return
  end

  def import_baby
    User.current = User.first
    
    remote_params = params
    remote_params = remote_params.reject{|key,value| key.match(/controller|action/) }
    
    result = ANCService.import_person_no_questions(remote_params) # rescue "Baby Addition Failed"

    render :text => result
  end

  # private
  def search_complete_url(found_person_id, primary_person_id, category)
		unless (primary_person_id.blank?)
			# Notice this swaps them!
			new_relationship_url(:patient_id => primary_person_id, :relation => found_person_id)
		else
			#
			# Hack reversed to continue testing overnight
			#
			# TODO: This needs to be redesigned!!!!!!!!!!!
			#
			#url_for(:controller => :encounters, :action => :new, :patient_id => found_person_id)

			people = PatientService.search_by_identifier(params[:identifier])
		 	patient = people.first.patient unless people.blank?

      params[:patient_id] = patient.id if patient
      params[:person][:id] = patient.id if patient
      found_person_id = patient.id if patient
      if create_from_dde_server
        p = DDEService::Patient.new(patient)
        identifier_type = PatientIdentifierType.find_by_name("National id")
        patient_national_id = patient.patient_identifiers.find_by_identifier_type(identifier_type.id).identifier rescue nil
        national_id_replaced = p.check_old_national_id(patient_national_id) unless patient_national_id.blank?
      end

			show_confirmation = CoreService.get_global_property_value('show.patient.confirmation').to_s == "true" rescue false
			if show_confirmation and patient
				url_for(:controller => :people, :action => :confirm , :patient_id => patient.id, :found_person_id =>found_person_id, :cat => category)
			else
       	next_task(patient)
			end
		end
	end

  def duplicates
    @duplicates = []
    people = PatientService.person_search(params[:search_params])
    people = []
    people.each do |person|
      @duplicates << PatientService.get_patient(person)
    end unless people == "found duplicate identifiers"

    if create_from_dde_server
      @remote_duplicates = []
      PatientService.search_from_dde_by_identifier(params[:search_params][:identifier]).each do |person|

        @remote_duplicates << PatientService.get_dde_person(person)
      end
    end

    @selected_identifier = params[:search_params][:identifier]
    render :layout => 'menu'
  end
 
  def reassign_dde_national_id
    person = DDEService.reassign_dde_identification(params[:dde_person_id],params[:local_person_id])
    redirect_to next_task(person.patient)
  end

  def remote_duplicates
    if params[:patient_id]
      @primary_patient = PatientService.get_patient(Person.find(params[:patient_id]))
    else
      @primary_patient = nil
    end
    
    @dde_duplicates = []
    if create_from_dde_server
      PatientService.search_from_dde_by_identifier(params[:identifier]).each do |person|
        @dde_duplicates << PatientService.get_dde_person(person)
      end
    end
	
    if @primary_patient.blank? and @dde_duplicates.blank?
      redirect_to :action => 'search',:identifier => params[:identifier] and return
    end
    render :layout => 'menu'
  end

	def create_person_from_dde                                                    
    person = DDEService.get_remote_person(params[:remote_person_id])                                                             
		#raise person.to_yaml
		if params[:cat] && params[:session_patient_id]
			url = "/relationships/new?patient_id=#{params[:session_patient_id]}&relation=#{person.id}&cat=#{params[:cat]}"
			redirect_to url and return
		end                    
    redirect_to next_task(person.patient)
  end

  def reassign_national_identifier
    patient = Patient.find(params[:person_id])
    if create_from_dde_server
      passed_params = PatientService.demographics(patient.person)
      new_npid = PatientService.create_from_dde_server_only(passed_params)
      npid = PatientIdentifier.new()
      npid.patient_id = patient.id
      npid.identifier_type = PatientIdentifierType.find_by_name('National ID').id
      npid.identifier = new_npid
      npid.save
    else
      PatientIdentifierType.find_by_name('National ID').next_identifier({:patient => patient})
    end
    npid = PatientIdentifier.find(:first,
      :conditions => ["patient_id = ? AND identifier = ?
           AND voided = 0", patient.id,params[:identifier]])
    npid.voided = 1
    npid.void_reason = "Given another national ID"
    npid.date_voided = Time.now()
    npid.voided_by = current_user.id
    npid.save
    
		if params[:cat] && params[:session_patient_id]
			url = "/relationships/new?patient_id=#{params[:session_patient_id]}&relation=#{patient.id}&cat=#{params[:cat]}"
			redirect_to url and return
		end     
    redirect_to next_task(patient)
  end

=begin
private
  
	def search_complete_url(found_person_id, primary_person_id)
		unless (primary_person_id.blank?)
			# Notice this swaps them!
			new_relationship_url(:patient_id => primary_person_id, :relation => found_person_id)
		else
			#
			# Hack reversed to continue testing overnight
			#
			# TODO: This needs to be redesigned!!!!!!!!!!!
			#
			#url_for(:controller => :encounters, :action => :new, :patient_id => found_person_id)
			patient = Person.find(found_person_id).patient
			show_confirmation = CoreService.get_global_property_value('show.patient.confirmation').to_s == "true" rescue false
			if show_confirmation
				#url_for(:controller => :people, :action => :confirm , :found_person_id =>found_person_id)
				url_for(:controller => :patients , :action => :pdash , :found_person_id =>found_person_id)
			else
				next_task(patient)
			end
		end
	end
=end
  def cul_age(birthdate , birthdate_estimated , date_created = Date.today, today = Date.today)
                                                                                
    # This code which better accounts for leap years                            
    patient_age = (today.year - birthdate.year) + ((today.month - birthdate.month) + ((today.day - birthdate.day) < 0 ? -1 : 0) < 0 ? -1 : 0)
                                                                                
    # If the birthdate was estimated this year, we round up the age, that way if
    # it is March and the patient says they are 25, they stay 25 (not become 24)
    birth_date = birthdate                                                      
    estimate = birthdate_estimated == 1                                         
    patient_age += (estimate && birth_date.month == 7 && birth_date.day == 1  &&
        today.month < birth_date.month && date_created.year == today.year) ? 1 : 0
  end                                                                           
                                                                                
  def birthdate_formatted(birthdate,birthdate_estimated)                        
    if birthdate_estimated == 1                                                 
      if birthdate.day == 1 and birthdate.month == 7                            
        birthdate.strftime("??/???/%Y")                                         
      elsif birthdate.day == 15                                                 
        birthdate.strftime("??/%b/%Y")                                          
      elsif birthdate.day == 1 and birthdate.month == 1                         
        birthdate.strftime("??/???/%Y")                                         
      end                                                                       
    else                                                                        
      birthdate.strftime("%d/%b/%Y")                                            
    end                                                                         
  end 
end
 
