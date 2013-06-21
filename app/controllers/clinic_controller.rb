class ClinicController < GenericClinicController
  def index    
    @facility = Location.current_health_center.name rescue ''

    @location = Location.find(session[:location_id]).name rescue ""

    @date = (session[:datetime].to_date rescue Date.today).strftime("%Y-%m-%d")

    @user = User.find(current_user.user_id) rescue nil

    @roles = User.find(current_user.user_id).user_roles.collect{|r| r.role} rescue []

    #delete session values used in reports, if any
    session.delete(:babies_map) if session[:babies_map]
    session.delete(:ids) if session[:ids]

    render :layout => 'dynamic-dashboard'
  end

  def reports
    @reports = [['/reports/select/','Report']]
    # render :template => 'clinic/reports', :layout => 'clinic'
    render :layout => false
  end

  def supervision
    @supervision_tools = [["Data that was Updated", "summary_of_records_that_were_updated"],
      ["Drug Adherence Level",    "adherence_histogram_for_all_patients_in_the_quarter"],
      ["Visits by Day",           "visits_by_day"],
      ["Non-eligible Patients in Cohort", "non_eligible_patients_in_cohort"]]

    @landing_dashboard = 'clinic_supervision'

    render :template => 'clinic/supervision', :layout => 'clinic' 
  end

  def properties
    render :template => 'clinic/properties', :layout => 'clinic' 
  end

  def printing
    render :template => 'clinic/printing', :layout => 'clinic' 
  end

  def users
    render :template => 'clinic/users', :layout => 'general'
  end

  def administration
    @reports = [['/clinic/users','User accounts/settings']]
    @landing_dashboard = 'clinic_administration'
    # render :template => 'clinic/administration', :layout => 'clinic'
    render :layout => false
  end

  def overview
    simple_overview_property = CoreService.get_global_property_value("simple_application_dashboard") rescue nil

    simple_overview = false
    if simple_overview_property != nil
      if simple_overview_property == 'true'
        simple_overview = true
      end
    end
    ids = Patient.find(:all, :select => "patient_id").collect{|p| p.id}
  
    @types = CoreService.get_global_property_value("statistics.show_encounter_types") rescue EncounterType.all.map(&:name).join(",")
    @types = @types.split(/,/)

    @males_me = Person.find(:all, :conditions => ['date_created BETWEEN ? AND ? AND creator =? AND gender =? AND person_id IN (?)',
        Date.today.strftime('%Y-%m-%d 00:00:00'),
        Date.today.strftime('%Y-%m-%d 23:59:59'),
        current_user.user_id, "M", ids]).collect{|baby|
      baby if ((baby.date_created.year - baby.birthdate.year) <= 1)
    } rescue [];
  
    @males_today = Person.find(:all, :conditions => ["date_created BETWEEN ? AND ? AND gender = ? AND person_id IN (?)",
        Date.today.strftime('%Y-%m-%d 00:00:00'),
        Date.today.strftime('%Y-%m-%d 23:59:59'),
        'M', ids]) rescue []
					 
    @males_year = Person.find(:all, :conditions => ["date_created BETWEEN ? AND ? AND gender = ? AND person_id IN (?)",
        Date.today.strftime('%Y-01-01 00:00:00'),
        Date.today.strftime('%Y-12-31 23:59:59'),
        'M', ids]) rescue [];
    @males_ever = Person.find(:all, :conditions => ["gender =?  AND person_id IN (?)", "M", ids]) rescue [];

    @females_me = Person.find(:all, :conditions => ['date_created BETWEEN ? AND ? AND creator =? AND gender =? AND person_id IN (?)',
        Date.today.strftime('%Y-%m-%d 00:00:00'),
        Date.today.strftime('%Y-%m-%d 23:59:59'),
        current_user.user_id, "F", ids]).collect{|baby|
      baby if ((baby.date_created.year - baby.birthdate.year) <= 1)
    } rescue [];
    
    @females_today = Person.find(:all, :conditions => ["date_created BETWEEN ? AND ? AND gender = ? AND person_id IN (?)",
        Date.today.strftime('%Y-%m-%d 00:00:00'),
        Date.today.strftime('%Y-%m-%d 23:59:59'),
        'F', ids]) rescue [];
    @females_year = Person.find(:all, :conditions => ["date_created BETWEEN ? AND ? AND gender = ? AND person_id IN (?)",
        Date.today.strftime('%Y-01-01 00:00:00'),
        Date.today.strftime('%Y-12-31 23:59:59'),
        'F', ids]) rescue [];
    @females_ever = Person.find(:all, :conditions => ["gender =? AND person_id IN (?)", "F", ids]) rescue [];
	
    @me = Encounter.statistics(@types,
      :conditions => ['encounter_datetime BETWEEN ? AND ? AND encounter.creator = ?',
        Date.today.strftime('%Y-%m-%d 00:00:00'),
        Date.today.strftime('%Y-%m-%d 23:59:59'),
        current_user.user_id])

    @me["REGISTRATION"] = (@males_me.length.to_i + @females_me.length.to_i).to_s

    @today = Encounter.statistics(@types,
      :conditions => ['encounter_datetime BETWEEN ? AND ?',
        Date.today.strftime('%Y-%m-%d 00:00:00'),
        Date.today.strftime('%Y-%m-%d 23:59:59')])

    @today["REGISTRATION"] = (@males_today.length.to_i + @females_today.length.to_i).to_s

    #if !simple_overview
    @year = Encounter.statistics(@types,
      :conditions => ['encounter_datetime BETWEEN ? AND ?',
        Date.today.strftime('%Y-01-01 00:00:00'),
        Date.today.strftime('%Y-12-31 23:59:59')])
        
    @year["REGISTRATION"] = (@males_year.length.to_i + @females_year.length.to_i).to_s

    @ever = Encounter.statistics(@types) rescue {}

    @ever["REGISTRATION"] = (@males_ever.length.to_i + @females_ever.length.to_i).to_s
    # end

    # raise current_user.to_yaml
    
    @user = current_user.name rescue ""
    if simple_overview
      render :template => 'clinic/overview_simple.rhtml' , :layout => false
      return
    end
    render :layout => false
  end

  def user_activities
    render :layout => false
  end
  
  def no_males
    render :layout => "error"
  end
  def serial_numbers
    @remaining_serial_numbers = SerialNumber.find(:all, :conditions => ["national_id IS NULL"]).size
    @print_string = (@remaining_serial_numbers ==1)?  "" + @remaining_serial_numbers.to_s + " Serial Number Remaining" : "" + @remaining_serial_numbers.to_s + " Serial Numbers Remaining"
    @limited_serial_numbers = (SerialNumber.all.size  <= 100) rescue false
    render :layout => false
  end  
  def link_error
    render :layout => "menu"
  end

  def malawi_regions

    @reports = []

    @reports << ['/location/new?act=create_district','Add District']
    @reports << ['/location/new?act=create_ta','Add TA']
    @reports << ['/location/new?act=create_village','Add Village']
    @reports << ['/location/new?act=view_villages','View Villages']
    @reports << ["/location/new?act=view_tas","View TA's"]
    @reports << ['/location/new?act=view_districts','View Districts']
    render :layout => false
  end
end
