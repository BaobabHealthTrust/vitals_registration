class LocationController < GenericLocationController

  def create_district
    region = params[:region]
    region = params[:region][:region_name] if region.blank?
    district = params[:value]
    
    region_id = Region.find_by_name(region).region_id rescue nil

    dist =  District.find_by_name_and_region_id(district, region_id) rescue nil

    District.create(:region_id => region_id,
      :date_created => Date.today,
      :creator => User.find_by_username("admin").user_id,
      :name => district ) rescue nil if !district.blank? and !region_id.blank? and dist.blank?
    redirect_to "/clinic"
  end rescue nil

  def create_ta
    region = params[:region]
    region = params[:region][:region_name] if region.blank?
    ta = params[:value]
    district = params[:district]

    region_id = Region.find_by_name(region).region_id rescue nil

    district_id = District.find_by_name_and_region_id(district, region_id).district_id rescue nil

    tao =  TraditionalAuthority.find_by_name_and_district_id(ta, district_id) rescue nil
    
    TraditionalAuthority.create(:district_id => district_id,
      :date_created => Date.today,
      :creator => User.find_by_username("admin").user_id,
      :name => ta ) rescue nil if !district_id.blank? and !ta.blank? and tao.blank?
    
    redirect_to "/clinic"
  end rescue nil

  def create_village
    region = params[:region]
    region = params[:region][:region_name] if region.blank?
    ta = params[:ta]
    village = params[:value]
    district = params[:district]

    region_id = Region.find_by_name(region).region_id rescue nil

    district_id = District.find_by_name_and_region_id(district, region_id).district_id rescue nil

    ta_id =  TraditionalAuthority.find_by_name_and_district_id(ta, district_id).traditional_authority_id rescue nil

    vg = Village.find_by_name_and_traditional_authority_id(village, traditional_authority_id) rescue nil

    Village.create(:traditional_authority_id => ta_id,
      :date_created => Date.today,
      :creator => User.find_by_username("admin").user_id,
      :name => village ) rescue nil if !ta_id.blank? and vg.blank? and !village.blank?

    redirect_to "/clinic"
  end

  def view
    
    region = params[:region]
    region = params[:region][:region_name] if region.blank?
    ta = params[:ta]
    value = params[:value]
    district = params[:district]
    @level = params[:level]

    region_id = Region.find_by_name(region).region_id rescue nil
    district_id = District.find_by_name_and_region_id(district, region_id)
    ta_id = TraditionalAuthority.find_by_name_and_district_id(ta, district_id).traditional_authority_id rescue nil

    case @level
    when "districts"
      @parent = region
      @list = District.find_all_by_region_id(region_id) rescue []
      
    when "tas"
      @parent = district + " District"
      @list = TraditionalAuthority.find_all_by_district_id(district_id) rescue []

    when "villages"      
      @parent = ta
      @list = Village.find_all_by_traditional_authority_id(ta_id) rescue []
      
    end
    
    render :layout => "menu"

  end

  def delete
    id = params[:id]
    level = params[:type]

    case level
    when "villages"
      vg = Village.find(id)
      vg.delete
    when "tas"
      ta = TraditionalAuthority.find(id)
      villages = Village.find_all_by_traditional_authority_id(ta.traditional_authority_id)

      (villages || []).each do |vg|
        vg.delete
      end

      ta.delete
      
    when "districts"
      district = District.find(id)

      tas = TraditionalAuthority.find_all_by_district_id(district.district_id)

      (tas || []).each do |tr|
        
        villages = Village.find_all_by_traditional_authority_id(tr.traditional_authority_id)

        (villages || []).each do |vg|
          vg.delete
        end

        tr.delete
      end

      district.delete
    end
    render :text => "done".to_json
  end
  
  def rename

    id = params[:id]
    level = params[:type]
    value = params[:name]
    
    case level
    when "villages"
    
      vg = Village.find(id)
      vg.update_attributes(:name => value)
      
    when "tas"
    
      ta = TraditionalAuthority.find(id)
      ta.update_attributes(:name => value)
      
    when "districts"
    
      district = District.find(id)

     	district.update_attributes(:name => value)      
     
    end

    redirect_to params[:return_url]
    
  end

  def merge_me
    id = params[:id]
    level = params[:type]
    @return_url = request.referrer
    @name = ""
    
    case level
    
    when "tas"

      ta = TraditionalAuthority.find(id) rescue nil
      @name = ta.name rescue ""
      @list = TraditionalAuthority.find_all_by_district_id(ta.district_id) rescue []

    when "districts"

      district = District.find(id)
      @name = district.name rescue ""
      @list = District.find_all_by_region_id(district.region_id) rescue []
     
    end
    
    @list.delete_if{|item| (item.id.to_s == id.to_s || item.name.length < 2 rescue false)} rescue nil
    
    @list_names = @list.collect{|li| li.name} rescue []

  end

  def merge
    id = params[:id]
    level = params[:type]
    value = params[:name]
    @names = params[:name]
    
    case level
   
    when "tas"

      ta = TraditionalAuthority.find(id)
      (@names || []).each do |name|
        merge_ta = TraditionalAuthority.find_by_name_and_district_id(name, ta.district_id)
        villages = Village.find_all_by_traditional_authority_id(merge_ta.traditional_authority_id)
        villages.each do |vg|
          check = Village.find_by_name_and_traditional_authority(vg.name, ta.traditional_authority_id) rescue nil
          vg.update_attributes(:traditional_authority_id => ta.traditional_authority_id) if check.blank?
          vg.delete if !check.blank?
        end
        
        merge_ta.delete
      end      
      
    when "districts"

      district = District.find(id)

      (@names || []).each do |name|
        merge_district = District.find_by_name_and_region_id(name, district.region_id)
        tas = TraditionalAuthority.find_all_by_district_id(merge_district.district_id)

        tas.each do |ta|

          check = TraditionalAuthority.find_by_name_and_district_id(ta.name, district.district_id) rescue nil

          if check.blank?
            ta.update_attributes(:district_id => district.district_id)
          else
            avail_vgs = Villages.find_all_by_traditional_authority_id(check.traditional_authority_id).collect{|v| v.name.downcase} rescue []
            villages = Villages.find_all_by_traditional_authority_id(ta.traditional_authority_id)
            villages.each do |village|
              if avail_vgs.include?(village.name.downcase)
                village.delete
              else
                village.update_attributes(:traditional_authority_id => check.traditional_authority_id)
              end
            end

            ta.delete
            
          end
          
        end
        
        merge_district.delete
      end      

    end

    redirect_to params[:return_url]
  end

end

