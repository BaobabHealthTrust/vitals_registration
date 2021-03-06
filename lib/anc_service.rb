module ANCService
  
  class ANC
    
    attr_accessor :patient, :person
    
    def initialize(patient)
      self.patient = patient
      self.person = self.patient.person
    end
   
    def national_id(force = true)
      id = self.patient.patient_identifiers.find_by_identifier_type(PatientIdentifierType.find_by_name("National id").id).identifier rescue nil
      return id unless force
      id ||= PatientIdentifierType.find_by_name("National id").next_identifier(:patient => self.patient).identifier
      id
    end

    def national_id_with_dashes(force = true)
      id = self.national_id(force)
      id[0..4] + "-" + id[5..8] + "-" + id[9..-1] rescue id
    end

    def serial_number
      self.patient.patient_identifiers.find_by_identifier_type(PatientIdentifierType.find_by_name("Serial Number").id).identifier rescue nil
    end

    def national_id_label
      return unless self.national_id
      sex =  self.patient.person.gender.match(/F/i) ? "(F)" : "(M)"
      address = self.address.strip[0..24].humanize.delete("'") rescue ""
      label = ZebraPrinter::StandardLabel.new
      label.font_size = 2
      label.font_horizontal_multiplier = 2
      label.font_vertical_multiplier = 2
      label.left_margin = 50
      label.draw_barcode(50,180,0,1,5,15,120,false,"#{self.national_id}")
      label.draw_multi_text("#{self.name.titleize.delete("'")}") #'
      label.draw_multi_text("#{self.national_id_with_dashes} #{self.birthdate_formatted}#{sex}")
      label.draw_multi_text("#{address}")
      label.print(1)
    end
  
    def visit_label(date = Date.today)
      label = ZebraPrinter::StandardLabel.new
      label.font_size = 3
      label.font_horizontal_multiplier = 1
      label.font_vertical_multiplier = 1
      label.left_margin = 50
      encs = encounters.find(:all,:conditions =>["DATE(encounter_datetime) = ?",date])
      return nil if encs.blank?
    
      label.draw_multi_text("Visit: #{encs.first.encounter_datetime.strftime("%d/%b/%Y %H:%M")}", :font_reverse => true)    
      encs.each {|encounter|
        next if encounter.name.humanize == "Registration"
        label.draw_multi_text("#{encounter.name.humanize}: #{encounter.to_s}", :font_reverse => false)
      }
      label.print(1)
    end  
  
    def get_identifier(type = 'National id')
      identifier_type = PatientIdentifierType.find_by_name(type)
      return if identifier_type.blank?
      identifiers = self.patient.patient_identifiers.find_all_by_identifier_type(identifier_type.id)
      return if identifiers.blank?
      identifiers.map{|i|i.identifier}.join(' , ') rescue nil
    end
  
    def current_weight
      obs = self.person.observations.recent(1).question("WEIGHT (KG)").all
      obs.last.value_numeric || obs.last.value_text rescue 0
    end
  
    def current_height
      obs = self.person.observations.recent(1).question("HEIGHT (CM)").all
      obs.last.value_numeric || obs.last.value_text rescue 0
    end
  
    def initial_weight
      obs = self.person.observations.recent(1).question("WEIGHT (KG)").all
      obs.first.value_numeric || obs.first.value_text rescue 0
    end
  
    def initial_height
      obs = self.person.observations.recent(1).question("HEIGHT (CM)").all
      obs.first.value_numeric || obs.first.value_text rescue 0
    end

    def initial_bmi
      obs = self.person.observations.recent(1).question("BMI").all
      obs.first.value_numeric rescue nil
    end

    def min_weight
      WeightHeight.min_weight(self.person.gender, self.age_in_months).to_f
    end
  
    def max_weight
      WeightHeight.max_weight(self.person.gender, self.age_in_months).to_f
    end
  
    def min_height
      WeightHeight.min_height(self.person.gender, self.age_in_months).to_f
    end
  
    def max_height
      WeightHeight.max_height(self.person.gender, self.age_in_months).to_f
    end
  
    def gender
      self.person.gender
    end

    def residence
      patient = Person.find(self.id)
      return patient.address
    end

    def active_range(date = Date.today)
      patient = self.patient rescue nil
    
      current_range = {}
    
      active_date = date
      
      pregnancies = {}; 
    
      # active_years = {}
    
      patient.encounters.find(:all, :order => ["encounter_datetime DESC"]).each{|e| 
        if e.name == "CURRENT PREGNANCY" && !pregnancies[e.encounter_datetime.strftime("%Y-%m-%d")]       
          pregnancies[e.encounter_datetime.strftime("%Y-%m-%d")] = {}        
        
          e.observations.each{|o| 
            concept = o.concept.concept_names.map(& :name).last rescue nil
            if concept
              # if !active_years[e.encounter_datetime.beginning_of_quarter.strftime("%Y-%m-%d")]                            
              if o.concept_id == (ConceptName.find_by_name("DATE OF LAST MENSTRUAL PERIOD").concept_id rescue nil)
                pregnancies[e.encounter_datetime.strftime("%Y-%m-%d")]["DATE OF LAST MENSTRUAL PERIOD"] = o.answer_string.squish          
                # active_years[e.encounter_datetime.beginning_of_quarter.strftime("%Y-%m-%d")] = true 
              end              
              # end
            end   
          } 
        end   
      }    
    
      # pregnancies = pregnancies.delete_if{|x, v| v == {}}
    
      # raise pregnancies.to_yaml
      
      pregnancies.each{|preg|
        if preg[1]["DATE OF LAST MENSTRUAL PERIOD"]
          preg[1]["START"] = preg[1]["DATE OF LAST MENSTRUAL PERIOD"].to_date
          preg[1]["END"] = preg[1]["DATE OF LAST MENSTRUAL PERIOD"].to_date + 7.day + 45.week # 9.month        
        else
          preg[1]["START"] = preg[0].to_date
          preg[1]["END"] = preg[0].to_date + 7.day + 45.week # 9.month
        end
      
        if active_date >= preg[1]["START"] && active_date <= preg[1]["END"]
          current_range["START"] = preg[1]["START"]
          current_range["END"] = preg[1]["END"]
        end
      }
    
      return [current_range, pregnancies]
    end
  
    def detailed_obstetric_history_label(date = Date.today)
      @patient = self.patient rescue nil
    
      @obstetrics = {}
      search_set = ["YEAR OF BIRTH", "PLACE OF BIRTH", "PREGNANCY", "LABOUR DURATION", 
        "METHOD OF DELIVERY", "CONDITION AT BIRTH", "BIRTH WEIGHT", "ALIVE", 
        "AGE AT DEATH", "UNITS OF AGE OF CHILD", "PROCEDURE DONE"]
      current_level = 0
    
      Encounter.find(:all, :conditions => ["encounter_type = ? AND patient_id = ?", 
          EncounterType.find_by_name("OBSTETRIC HISTORY").id, @patient.id]).each{|e| 
        e.observations.each{|obs|
          concept = obs.concept.concept_names.map(& :name).last rescue nil
          if(!concept.nil?)
            if search_set.include?(concept.upcase)
              if obs.concept_id == (ConceptName.find_by_name("YEAR OF BIRTH").concept_id rescue nil)
                current_level += 1
            
                @obstetrics[current_level] = {}
              end
          
              if @obstetrics[current_level]
                @obstetrics[current_level][concept.upcase] = obs.answer_string rescue nil
              
                if obs.concept_id == (ConceptName.find_by_name("YEAR OF BIRTH").concept_id rescue nil) && obs.answer_string.to_i == 0
                  @obstetrics[current_level]["YEAR OF BIRTH"] = "Unknown"
                end
              end
                        
            end
          end
        }      
      }
    
      # raise @anc_patient.to_yaml
    
      @pregnancies = self.active_range
    
      @range = []
    
      @pregnancies = @pregnancies[1]
    
      @pregnancies.each{|preg|
        @range << preg[0].to_date
      }
    
      @range = @range.sort    
    
      @range.each{|y|
        current_level += 1
        @obstetrics[current_level] = {}
        @obstetrics[current_level]["YEAR OF BIRTH"] = y.year
        @obstetrics[current_level]["PLACE OF BIRTH"] = "<b>(Here)</b>"
      }
    
      label = ZebraPrinter::StandardLabel.new
      label2 = ZebraPrinter::StandardLabel.new
      label2set = false
      label3 = ZebraPrinter::StandardLabel.new
      label3set = false

      label.draw_text("Detailed Obstetric History",28,29,0,1,1,2,false)
      label.draw_text("Pr.",25,65,0,2,1,1,false)
      label.draw_text("No.",25,85,0,2,1,1,false)
      label.draw_text("Year",59,65,0,2,1,1,false)
      label.draw_text("Place",110,65,0,2,1,1,false)
      label.draw_text("Gest.",225,65,0,2,1,1,false)
      label.draw_text("months",223,85,0,2,1,1,false)
      label.draw_text("Labour",305,65,0,2,1,1,false)
      label.draw_text("durat.",305,85,0,2,1,1,false)
      label.draw_text("(hrs)",310,105,0,2,1,1,false)
      label.draw_text("Delivery",405,65,0,2,1,1,false)
      label.draw_text("Method",410,85,0,2,1,1,false)
      label.draw_text("Conditi.",518,65,0,2,1,1,false)
      label.draw_text("at birth",518,85,0,2,1,1,false)
      label.draw_text("Birt.",625,65,0,2,1,1,false)
      label.draw_text("weigh.",620,85,0,2,1,1,false)
      label.draw_text("(kg)",625,105,0,2,1,1,false)
      label.draw_text("Aliv.",690,65,0,2,1,1,false)
      label.draw_text("now?",690,85,0,2,1,1,false)
      label.draw_text("Age at",745,65,0,2,1,1,false)
      label.draw_text("death*",745,85,0,2,1,1,false)
    
      label.draw_line(20,60,800,2,0)
      label.draw_line(20,60,2,245,0)
      label.draw_line(20,305,800,2,0)
      label.draw_line(805,60,2,245,0)
      label.draw_line(20,125,800,2,0)
    
      label.draw_line(56,60,2,245,0)
      label.draw_line(105,60,2,245,0)
      label.draw_line(220,60,2,245,0)
      label.draw_line(295,60,2,245,0)
      label.draw_line(380,60,2,245,0)
      label.draw_line(510,60,2,245,0)
      label.draw_line(615,60,2,245,0)
      label.draw_line(683,60,2,245,0)
      label.draw_line(740,60,2,245,0)
    
      (1..(@obstetrics.length + 1)).each do |pos|
      
        @place = (@obstetrics[pos] ? (@obstetrics[pos]["PLACE OF BIRTH"] ? 
              @obstetrics[pos]["PLACE OF BIRTH"] : "") : "").gsub(/Centre/i, 
          "C.").gsub(/Health/i, "H.").gsub(/Center/i, "C.")
          
        @gest = (@obstetrics[pos] ? (@obstetrics[pos]["PREGNANCY"] ? 
              @obstetrics[pos]["PREGNANCY"] : "") : "")
          
        @gest = (@gest.length > 5 ? truncate(@gest, 5) : @gest)
              
        @delmode = (@obstetrics[pos] ? (@obstetrics[pos]["METHOD OF DELIVERY"] ? 
              @obstetrics[pos]["METHOD OF DELIVERY"].titleize : (@obstetrics[pos]["PROCEDURE DONE"] ? 
                @obstetrics[pos]["PROCEDURE DONE"] : "")) : "").gsub(/Spontaneous\sVaginal\sDelivery/i, 
          "S.V.D.").gsub(/Caesarean\sSection/i, "C-Section").gsub(/Vacuum\sExtraction\sDelivery/i, 
          "Vac. Extr.").gsub("(MVA)", "").gsub(/Manual\sVacuum\sAspiration/i, 
          "M.V.A.").gsub(/Evacuation/i, "Evac")
             
        @labor = (@obstetrics[pos] ? (@obstetrics[pos]["LABOUR DURATION"] ? 
              @obstetrics[pos]["LABOUR DURATION"] : "") : "")
             
        @labor = (@labor.length > 5 ? truncate(@labor,5) : @labor)
        
        @cond = (@obstetrics[pos] ? (@obstetrics[pos]["CONDITION AT BIRTH"] ? 
              @obstetrics[pos]["CONDITION AT BIRTH"] : "") : "").titleize
        
        @birt_weig = (@obstetrics[pos] ? (@obstetrics[pos]["BIRTH WEIGHT"] ? 
              @obstetrics[pos]["BIRTH WEIGHT"] : "") : "")
      
        @dea = (@obstetrics[pos] ? (@obstetrics[pos]["AGE AT DEATH"] ? 
              (@obstetrics[pos]["AGE AT DEATH"].to_s.match(/\.[1-9]/) ? @obstetrics[pos]["AGE AT DEATH"] : 
                @obstetrics[pos]["AGE AT DEATH"].to_i) : "") : "").to_s + 
          (@obstetrics[pos] ? (@obstetrics[pos]["UNITS OF AGE OF CHILD"] ? 
              @obstetrics[pos]["UNITS OF AGE OF CHILD"] : "") : "")
      
        if pos <= 3
        
          label.draw_text(pos,28,(85 + (60 * pos)),0,2,1,1,false)
        
          label.draw_text((@obstetrics[pos] ? (@obstetrics[pos]["YEAR OF BIRTH"] ? 
                  (@obstetrics[pos]["YEAR OF BIRTH"].to_i > 0 ? @obstetrics[pos]["YEAR OF BIRTH"].to_i : 
                    "????") : "") : ""),58,(70 + (60 * pos)),0,2,1,1,false)
                
          if @place.length < 9
            label.draw_text(@place,111,(70 + (60 * pos)),0,2,1,1,false)
          else
            @place = paragraphate(@place)
        
            (0..(@place.length)).each{|p|
              label.draw_text(@place[p],111,(70 + (60 * pos) + (18 * p)),0,2,1,1,false)
            }
          end
          
          label.draw_text(@gest,225,(70 + (60 * pos)),0,2,1,1,false)
            
          label.draw_text(@labor,300,(70 + (60 * pos)),0,2,1,1,false)
             
          if @delmode.length < 11
            label.draw_text(@delmode,385,(70 + (60 * pos)),0,2,1,1,false)
          else
            @delmode = paragraphate(@delmode)
        
            (0..(@delmode.length)).each{|p|
              label.draw_text(@delmode[p],385,(70 + (60 * pos) + (13 * p)),0,2,1,1,false)
            }
          end
        
          if @cond.length < 6
            label.draw_text(@cond,515,(70 + (60 * pos)),0,2,1,1,false)
          else
            @cond = paragraphate(@cond, 6)
        
            (0..(@cond.length)).each{|p|
              label.draw_text(@cond[p],515,(70 + (60 * pos) + (18 * p)),0,2,1,1,false)
            }
          end
        
          if @birt_weig.length < 6
            label.draw_text(@birt_weig,620,(70 + (60 * pos)),0,2,1,1,false)
          else
            @birt_weig = paragraphate(@birt_weig, 4)
        
            (0..(@birt_weig.length)).each{|p|
              label.draw_text(@birt_weig[p],620,(70 + (60 * pos) + (18 * p)),0,2,1,1,false)
            }
          end
                        
          label.draw_text((@obstetrics[pos] ? (@obstetrics[pos]["ALIVE"] ? 
                  @obstetrics[pos]["ALIVE"] : "") : ""),687,(70 + (60 * pos)),0,2,1,1,false)
        
          if @dea.length < 6
            label.draw_text(@dea,745,(70 + (60 * pos)),0,2,1,1,false)
          else
            @dea = paragraphate(@dea, 4)
        
            (0..(@dea.length)).each{|p|
              label.draw_text(@dea[p],745,(70 + (60 * pos) + (18 * p)),0,2,1,1,false)
            }
          end
           
          label.draw_line(20,((135 + (45 * pos)) <= 305 ? (125 + (60 * pos)) : 305),800,2,0)
        
        elsif pos >= 4 && pos <= 8
          if pos == 4
            label2.draw_line(20,30,800,2,0)
            label2.draw_line(20,30,2,275,0)
            label2.draw_line(20,305,800,2,0)
            label2.draw_line(805,30,2,275,0)
          
            label2.draw_line(55,30,2,275,0)
            label2.draw_line(105,30,2,275,0)
            label2.draw_line(220,30,2,275,0)
            label2.draw_line(295,30,2,275,0)
            label2.draw_line(380,30,2,275,0)
            label2.draw_line(510,30,2,275,0)
            label2.draw_line(615,30,2,275,0)
            label2.draw_line(683,30,2,275,0)
            label2.draw_line(740,30,2,275,0)
          end
          label2.draw_text(pos,28,((55 * (pos - 3))),0,2,1,1,false)
        
          label2.draw_text((@obstetrics[pos] ? (@obstetrics[pos]["YEAR OF BIRTH"] ? 
                  (@obstetrics[pos]["YEAR OF BIRTH"].to_i > 0 ? @obstetrics[pos]["YEAR OF BIRTH"].to_i : 
                    "????") : "") : ""),58,((55 * (pos - 3)) - 13),0,2,1,1,false)
        
          if @place.length < 8
            label2.draw_text(@place,111,((55 * (pos - 3)) - 13),0,2,1,1,false)
          else
            @place = paragraphate(@place)
        
            (0..(@place.length)).each{|p|
              label2.draw_text(@place[p],111,(55 * (pos - 3) + (18 * p))-17,0,2,1,1,false)
            }
          end
        
          label2.draw_text(@gest,225,((55 * (pos - 3)) - 13),0,2,1,1,false)
        
          label2.draw_text(@labor,300,((55 * (pos - 3)) - 13),0,2,1,1,false)
        
          if @delmode.length < 11
            label2.draw_text(@delmode,385,(55 * (pos - 3)),0,2,1,1,false)
          else
            @delmode = paragraphate(@delmode)
        
            (0..(@delmode.length)).each{|p|
              label2.draw_text(@delmode[p],385,(55 * (pos - 3) + (18 * p))-17,0,2,1,1,false)
            }
          end
        
          if @cond.length < 6
            label2.draw_text(@cond,515,((55 * (pos - 3)) - 13),0,2,1,1,false)
          else
            @cond = paragraphate(@cond, 6)
        
            (0..(@cond.length)).each{|p|
              label2.draw_text(@cond[p],515,(55 * (pos - 3) + (18 * p))-17,0,2,1,1,false)
            }
          end
        
          if @birt_weig.length < 6
            label2.draw_text(@birt_weig,620,((55 * (pos - 3)) - 13),0,2,1,1,false)
          else
            @birt_weig = paragraphate(@birt_weig, 4)
        
            (0..(@birt_weig.length)).each{|p|
              label2.draw_text(@birt_weig[p],620,(55 * (pos - 3) + (18 * p))-17,0,2,1,1,false)
            }
          end
           
          label2.draw_text((@obstetrics[pos] ? (@obstetrics[pos]["ALIVE"] ? 
                  @obstetrics[pos]["ALIVE"] : "") : ""),687,((55 * (pos - 3)) - 13),0,2,1,1,false)
        
          if @dea.length < 6
            label2.draw_text(@dea,745,((55 * (pos - 3)) - 13),0,2,1,1,false)
          else
            @dea = paragraphate(@dea, 4)
        
            (0..(@dea.length)).each{|p|
              label2.draw_text(@dea[p],745,(55 * (pos - 3) + (18 * p))-17,0,2,1,1,false)
            }
          end
           
          label2.draw_line(20,(((55 * (pos - 3)) + 35) <= 305 ? ((55 * (pos - 3)) + 35) : 305),800,2,0)
          label2set = true
        else
          if pos == 9
            label3.draw_line(20,30,800,2,0)
            label3.draw_line(20,30,2,275,0)
            label3.draw_line(20,305,800,2,0)
            label3.draw_line(805,30,2,275,0)
          
            label3.draw_line(55,30,2,275,0)
            label3.draw_line(105,30,2,275,0)
            label3.draw_line(220,30,2,275,0)
            label3.draw_line(295,30,2,275,0)
            label3.draw_line(380,30,2,275,0)
            label3.draw_line(510,30,2,275,0)
            label3.draw_line(615,30,2,275,0)
            label3.draw_line(683,30,2,275,0)
            label3.draw_line(740,30,2,275,0)
          end
          label3.draw_text(pos,28,((55 * (pos - 8))),0,2,1,1,false)
        
          label3.draw_text((@obstetrics[pos] ? (@obstetrics[pos]["YEAR OF BIRTH"] ? 
                  (@obstetrics[pos]["YEAR OF BIRTH"].to_i > 0 ? @obstetrics[pos]["YEAR OF BIRTH"].to_i : 
                    "????") : "") : ""),58,((55 * (pos - 8)) - 13),0,2,1,1,false)
        
          if @place.length < 8
            label3.draw_text(@place,111,((55 * (pos - 8)) - 13),0,2,1,1,false)
          else
            @place = paragraphate(@place)
        
            (0..(@place.length)).each{|p|
              label3.draw_text(@place[p],111,(55 * (pos - 8) + (18 * p))-17,0,2,1,1,false)
            }
          end
        
          label3.draw_text(@gest,225,((55 * (pos - 8)) - 13),0,2,1,1,false)
        
          label3.draw_text(@labor,300,((55 * (pos - 8)) - 13),0,2,1,1,false)
        
          if @delmode.length < 11
            label3.draw_text(@delmode,385,(55 * (pos - 8)),0,2,1,1,false)
          else
            @delmode = paragraphate(@delmode)
        
            (0..(@delmode.length)).each{|p|
              label3.draw_text(@delmode[p],385,(55 * (pos - 8) + (18 * p))-17,0,2,1,1,false)
            }
          end
        
          if @cond.length < 6
            label3.draw_text(@cond,515,((55 * (pos - 8)) - 13),0,2,1,1,false)
          else
            @cond = paragraphate(@cond, 6)
        
            (0..(@cond.length)).each{|p|
              label3.draw_text(@cond[p],515,(55 * (pos - 8) + (18 * p))-17,0,2,1,1,false)
            }
          end
        
          if @birt_weig.length < 6
            label3.draw_text(@birt_weig,620,(70 + (60 * pos)),0,2,1,1,false)
          else
            @birt_weig = paragraphate(@birt_weig, 4)
        
            (0..(@birt_weig.length)).each{|p|
              label3.draw_text(@birt_weig[p],620,(55 * (pos - 3) + (18 * p))-17,0,2,1,1,false)
            }
          end
          
          label3.draw_text((@obstetrics[pos] ? (@obstetrics[pos]["ALIVE"] ? 
                  @obstetrics[pos]["ALIVE"] : "") : ""),687,((55 * (pos - 8)) - 13),0,2,1,1,false)
        
          if @dea.length < 6
            label3.draw_text(@dea,745,((55 * (pos - 3)) - 13),0,2,1,1,false)
          else
            @dea = paragraphate(@dea, 4)
        
            (0..(@dea.length)).each{|p|
              label3.draw_text(@dea[p],745,(55 * (pos - 3) + (18 * p))-17,0,2,1,1,false)
            }
          end
           
          label3.draw_line(20,(((55 * (pos - 8)) + 35) <= 305 ? ((55 * (pos - 8)) + 35) : 305),800,2,0)
          label3set = true
        end
      
      end
    
      if label3set
        label.print(1) + label2.print(1) + label3.print(1)
      elsif label2set
        label.print(1) + label2.print(1)
      else
        label.print(1)
      end    
    end
  
    def obstetric_medical_history_label(date = Date.today)
      @patient = self.patient rescue nil
     
      @pregnancies = self.active_range
    
      @range = []
    
      @pregnancies = @pregnancies[1]
    
      @pregnancies.each{|preg|
        @range << preg[0].to_date
      }
    
      @deliveries = Observation.find(:last,
        :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
          Encounter.find(:all).collect{|e| e.encounter_id},
          ConceptName.find_by_name('PARITY').concept_id]).answer_string.squish.to_i rescue nil

      @deliveries = @deliveries + (@range.length > 0 ? @range.length - 1 : @range.length) if !@deliveries.nil?
    
      @gravida = Observation.find(:last,
        :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
          Encounter.find(:all).collect{|e| e.encounter_id},
          ConceptName.find_by_name('GRAVIDA').concept_id]).answer_string.squish.to_i rescue nil

      @multipreg = Observation.find(:last,
        :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
          Encounter.find(:all, :conditions => ["encounter_type = ?", 
              EncounterType.find_by_name("OBSTETRIC HISTORY").id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('MULTIPLE GESTATION').concept_id]).answer_string.squish rescue nil

      @abortions = Observation.find(:last,
        :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
          Encounter.find(:all).collect{|e| e.encounter_id},
          ConceptName.find_by_name('NUMBER OF ABORTIONS').concept_id]).answer_string.squish.to_i rescue nil

      @stillbirths = Observation.find(:last,
        :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
          Encounter.find(:all).collect{|e| e.encounter_id},
          ConceptName.find_by_name('STILL BIRTH').concept_id]).answer_string.squish rescue nil

      #Observation.find(:all, :conditions => ["person_id = ? AND encounter_id IN (?) AND value_coded = ?", 40, Encounter.active.find(:all, :conditions => ["patient_id = ?", 40]).collect{|e| e.encounter_id}, ConceptName.find_by_name('Caesarean section').concept_id])
    
      @csections = Observation.find(:all,
        :conditions => ["person_id = ? AND encounter_id IN (?) AND (concept_id = ? AND value_coded = ?)", @patient.id,
          Encounter.find(:all, :conditions => ["patient_id = ?", @patient.id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('Caesarean section').concept_id, ConceptName.find_by_name('Yes').concept_id]).length rescue nil

      @vacuum = Observation.find(:all,
        :conditions => ["person_id = ? AND encounter_id IN (?) AND value_coded = ?", @patient.id,
          Encounter.find(:all, :conditions => ["patient_id = ?", @patient.id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('Vacuum extraction delivery').concept_id]).length rescue nil

      @symphosio = Observation.find(:last, 
        :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
          Encounter.find(:all).collect{|e| e.encounter_id},
          ConceptName.find_by_name('SYMPHYSIOTOMY').concept_id]).answer_string.squish rescue nil

      @haemorrhage = Observation.find(:last,
        :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
          Encounter.find(:all).collect{|e| e.encounter_id},
          ConceptName.find_by_name('HEMORRHAGE').concept_id]).answer_string.squish rescue nil

      @preeclampsia = Observation.find(:last,
        :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?", @patient.id,
          Encounter.find(:all).collect{|e| e.encounter_id},
          ConceptName.find_by_name('PRE-ECLAMPSIA').concept_id]).answer_string.squish rescue nil

      @asthma = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
          @patient.id, Encounter.find(:all, :conditions => ["patient_id = ?", @patient.id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('ASTHMA').concept_id]).answer_string.squish.upcase rescue nil

      @hyper = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
          @patient.id, Encounter.find(:all, :conditions => ["patient_id = ?", @patient.id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('HYPERTENSION').concept_id]).answer_string.squish.upcase rescue nil

      @diabetes = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
          @patient.id, Encounter.find(:all, :conditions => ["patient_id = ?", @patient.id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('DIABETES').concept_id]).answer_string.squish.upcase rescue nil

      @epilepsy = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
          @patient.id, Encounter.find(:all, :conditions => ["patient_id = ?", @patient.id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('EPILEPSY').concept_id]).answer_string.squish.upcase rescue nil

      @renal = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
          @patient.id, Encounter.find(:all, :conditions => ["patient_id = ?", @patient.id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('RENAL DISEASE').concept_id]).answer_string.squish.upcase rescue nil

      @fistula = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
          @patient.id, Encounter.find(:all, :conditions => ["patient_id = ?", @patient.id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('FISTULA REPAIR').concept_id]).answer_string.squish.upcase rescue nil

      @deform = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
          @patient.id, Encounter.find(:all, :conditions => ["patient_id = ?", @patient.id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('SPINE OR LEG DEFORM').concept_id]).answer_string.squish.upcase rescue nil

      @surgicals = Observation.find(:all, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
          @patient.id, Encounter.find(:all, :conditions => ["patient_id = ? AND encounter_type = ?", 
              @patient.id, EncounterType.find_by_name("SURGICAL HISTORY").id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('PROCEDURE DONE').concept_id]).collect{|o| 
        "#{o.answer_string.squish} (#{o.obs_datetime.strftime('%d-%b-%Y')})"} rescue []

      @age = self.age rescue 0

      label = ZebraPrinter::StandardLabel.new

      label.draw_text("Obstetric History",28,29,0,1,1,2,false)
      label.draw_text("Medical History",400,29,0,1,1,2,false)
      label.draw_text("Refer",750,29,0,1,1,2,true)
      label.draw_line(25,60,172,1,0)
      label.draw_line(400,60,152,1,0)
      label.draw_text("Gravida",28,80,0,2,1,1,false)
      label.draw_text("Asthma",400,80,0,2,1,1,false)
      label.draw_text("Deliveries",28,110,0,2,1,1,false)
      label.draw_text("Hypertension",400,110,0,2,1,1,false)
      label.draw_text("Abortions",28,140,0,2,1,1,false)
      label.draw_text("Diabetes",400,140,0,2,1,1,false)
      label.draw_text("Still Births",28,170,0,2,1,1,false)
      label.draw_text("Epilepsy",400,170,0,2,1,1,false)
      label.draw_text("Vacuum Extraction",28,200,0,2,1,1,false)
      label.draw_text("Renal Disease",400,200,0,2,1,1,false)
      # label.draw_text("Symphisiotomy",28,230,0,2,1,1,false)
      label.draw_text("C/Section",28,230,0,2,1,1,false)
      label.draw_text("Fistula Repair",400,230,0,2,1,1,false)
      label.draw_text("Haemorrhage",28,260,0,2,1,1,false)
      label.draw_text("Leg/Spine Deformation",400,260,0,2,1,1,false)
      label.draw_text("Pre-Eclampsia",28,290,0,2,1,1,false)
      label.draw_text("Age",400,290,0,2,1,1,false)
      label.draw_line(250,70,130,1,0)
      label.draw_line(250,70,1,236,0)
      label.draw_line(250,306,130,1,0)
      label.draw_line(380,70,1,236,0)
      label.draw_line(250,100,130,1,0)
      label.draw_line(250,130,130,1,0)
      label.draw_line(250,160,130,1,0)
      label.draw_line(250,190,130,1,0)
      label.draw_line(250,220,130,1,0)
      label.draw_line(250,250,130,1,0)
      label.draw_line(250,280,130,1,0)
      label.draw_line(659,70,130,1,0)
      label.draw_line(659,70,1,236,0)
      label.draw_line(659,306,130,1,0)
      label.draw_line(790,70,1,236,0)
      label.draw_line(659,100,130,1,0)
      label.draw_line(659,130,130,1,0)
      label.draw_line(659,160,130,1,0)
      label.draw_line(659,190,130,1,0)
      label.draw_line(659,220,130,1,0)
      label.draw_line(659,250,130,1,0)
      label.draw_line(659,280,130,1,0)
      label.draw_text("#{@gravida}",280,80,0,2,1,1,false)
      label.draw_text("#{@deliveries}",280,110,0,2,1,1,(@deliveries > 4 ? true : false))
      label.draw_text("#{@abortions}",280,140,0,2,1,1,(@abortions > 1 ? true : false))
      label.draw_text("#{(!@stillbirths.nil? ? (@stillbirths.upcase == "NO" ? "NO" : "YES") : "")}",280,170,0,2,1,1,
        (!@stillbirths.nil? ? (@stillbirths.upcase == "NO" ? false : true) : false))
      label.draw_text("#{(!@vacuum.nil? ? (@vacuum > 0 ? "YES" : "NO") : "")}",280,200,0,2,1,1,
        (!@vacuum.nil? ? (@vacuum > 0 ? true : false) : false))
      # label.draw_text("#{(!@symphosio.nil? ? (@symphosio.upcase == "NO" ? "NO" : "YES") : "")}",280,230,0,2,1,1,
      #   (!@symphosio.nil? ? (@symphosio.upcase == "NO" ? false : true) : false))
      label.draw_text("#{(!@csections.nil? ? (@csections <= 0 ? "NO" : "YES") : "")}",280,230,0,2,1,1,
        (!@csections.nil? ? (@csections <= 0 ? false : true) : false))
      label.draw_text("#{@haemorrhage}",280,260,0,2,1,1,(@haemorrhage.upcase == "PPH" ? true : false))
      label.draw_text("#{(!@preeclampsia.nil? ? (@preeclampsia.upcase == "NO" ? "NO" : "YES") : "")}",280,285,0,2,1,1,
        (!@preeclampsia.nil? ? (@preeclampsia.upcase == "NO" ? false : true) : false))
    
      label.draw_text("#{(!@asthma.nil? ? (@asthma.upcase == "NO" ? "NO" : "YES") : "")}",690,80,0,2,1,1,
        (!@asthma.nil? ? (@asthma.upcase == "NO" ? false : true) : false))
      label.draw_text("#{(!@hyper.nil? ? (@hyper.upcase == "NO" ? "NO" : "YES") : "")}",690,110,0,2,1,1,
        (!@hyper.nil? ? (@hyper.upcase == "NO" ? false : true) : false))
      label.draw_text("#{(!@diabetes.nil? ? (@diabetes.upcase == "NO" ? "NO" : "YES") : "")}",690,140,0,2,1,1,
        (!@diabetes.nil? ? (@diabetes.upcase == "NO" ? false : true) : false))
      label.draw_text("#{(!@epilepsy.nil? ? (@epilepsy.upcase == "NO" ? "NO" : "YES") : "")}",690,170,0,2,1,1,
        (!@epilepsy.nil? ? (@epilepsy.upcase == "NO" ? false : true) : false))
      label.draw_text("#{(!@renal.nil? ? (@renal.upcase == "NO" ? "NO" : "YES") : "")}",690,200,0,2,1,1,
        (!@renal.nil? ? (@renal == "NO" ? false : true) : false))
      label.draw_text("#{(!@fistula.nil? ? (@fistula.upcase == "NO" ? "NO" : "YES") : "")}",690,230,0,2,1,1,
        (!@fistula.nil? ? (@fistula.upcase == "NO" ? false : true) : false))
      label.draw_text("#{(!@deform.nil? ? (@deform.upcase == "NO" ? "NO" : "YES") : "")}",690,260,0,2,1,1,
        (!@deform.nil? ? (@deform == "NO" ? false : true) : false))
      label.draw_text("#{@age}",690,285,0,2,1,1,
        (((@age > 0 && @age < 16) || (@age > 40)) ? true : false))

      label.print(1)
    end
  
    def examination_label(target_date = Date.today)
      @patient = self.patient rescue nil

      syphil = {}
      @patient.encounters.find(:all, :conditions => ["encounter_type IN (?)", 
          EncounterType.find_by_name("LAB RESULTS").id]).each{|e| 
        e.observations.each{|o| 
          syphil[o.concept.concept_names.map(& :name).last.upcase] = o.answer_string.squish.upcase
        }      
      }
    
      @syphilis = syphil["SYPHILIS TEST RESULT"].titleize rescue nil

      @syphilis_date = syphil["SYPHILIS TEST RESULT DATE"] rescue nil

      @hiv_test = syphil["HIV STATUS"].titleize rescue nil

      @hiv_test_date = syphil["HIV TEST DATE"] rescue nil

      hb = {}; pos = 1; 
    
      @patient.encounters.find(:all, 
        :order => "encounter_datetime DESC", :conditions => ["encounter_type = ?", 
          EncounterType.find_by_name("LAB RESULTS").id]).each{|e| 
        e.observations.each{|o| hb[o.concept.concept_names.map(& :name).last.upcase + " " + 
              pos.to_s] = o.answer_string.squish.upcase; pos += 1 if o.concept.concept_names.map(& :name).last.upcase == "HB TEST RESULT DATE";
        }      
      }
    
      @hb1 = hb["HB TEST RESULT 1"] rescue nil

      @hb1_date = hb["HB TEST RESULT DATE 1"] rescue nil

      @hb2 = hb["HB TEST RESULT 2"] rescue nil

      @hb2_date = hb["HB TEST RESULT DATE 2"] rescue nil

      @cd4 = syphil['CD4 COUNT'] rescue nil

      @cd4_date = syphil['CD4 COUNT DATETIME'] rescue nil

      @height = current_height.to_i # rescue nil

      @multiple = Observation.find(:last, :conditions => ["person_id = ? AND encounter_id IN (?) AND concept_id = ?",
          @patient.id, Encounter.find(:all, :conditions => ["encounter_type = ?", 
              EncounterType.find_by_name("CURRENT PREGNANCY").id]).collect{|e| e.encounter_id},
          ConceptName.find_by_name('Multiple Gestation').concept_id]).answer_string.squish rescue nil

      @who = Encounter.find_by_sql("SELECT who_stage(#{@patient.id}, #{(session[:datetime] ? 
        session[:datetime].to_date : Date.today)})") rescue nil

      label = ZebraPrinter::StandardLabel.new   
    
      label.draw_text("Examination",28,29,0,1,1,2,false)
      label.draw_line(25,55,115,1,0)
      label.draw_line(25,190,115,1,0)
      label.draw_text("Height",28,76,0,2,1,1,false)
      label.draw_text("Multiple Pregnancy",28,106,0,2,1,1,false)
      label.draw_text("WHO Clinical Stage",28,136,0,2,1,1,false)
      label.draw_text("Lab Results",28,161,0,1,1,2,false)
      label.draw_text("Date",190,170,0,2,1,1,false)
      label.draw_text("Result",325,170,0,2,1,1,false)
      label.draw_text("HIV",28,196,0,2,1,1,false)
      label.draw_text("Syphilis",28,226,0,2,1,1,false)
      label.draw_text("Hb1",28,256,0,2,1,1,false)
      label.draw_text("Hb2",28,286,0,2,1,1,false)
      label.draw_line(260,70,170,1,0)
      label.draw_line(260,70,1,90,0)
      label.draw_line(180,306,250,1,0)
      label.draw_line(430,70,1,90,0)
    
      label.draw_line(180,190,1,115,0)
      label.draw_line(320,190,1,115,0)
      label.draw_line(430,190,1,115,0)
    
      label.draw_line(260,100,170,1,0)    
      label.draw_line(260,130,170,1,0)
      label.draw_line(260,160,170,1,0)
    
      label.draw_line(180,190,250,1,0)
      label.draw_line(180,220,250,1,0)
      label.draw_line(180,250,250,1,0)
      label.draw_line(180,280,250,1,0)
    
      label.draw_text(@height,270,76,0,2,1,1,false)
      label.draw_text(@multiple,270,106,0,2,1,1,false)
      label.draw_text(@who,270,136,0,2,1,1,false)
        
      label.draw_text(@hiv_test_date,190,196,0,2,1,1,false)
      label.draw_text(@syphilis_date,190,226,0,2,1,1,false)
      label.draw_text(@hb1_date,190,256,0,2,1,1,false)
      label.draw_text(@hb2_date,190,286,0,2,1,1,false)
        
      label.draw_text(@hiv_test,325,196,0,2,1,1,false)
      label.draw_text(@syphilis,325,226,0,2,1,1,false)
      label.draw_text(@hb1,325,256,0,2,1,1,false)
      label.draw_text(@hb2,325,286,0,2,1,1,false)
    
      label.print(1)
    end
  
    def visit_summary_label(target_date = Date.today)
      @patient = self.patient rescue nil
    
      @current_range = self.active_range(target_date.to_date)

      # raise @current_range.to_yaml
    
      encounters = {}

      @patient.encounters.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
          @current_range[0]["START"], @current_range[0]["END"]]).collect{|e|    
        encounters[e.encounter_datetime.strftime("%d/%b/%Y")] = {"USER" => User.find(e.creator).name}      
      }

      @patient.encounters.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
          @current_range[0]["START"], @current_range[0]["END"]]).collect{|e| 
        encounters[e.encounter_datetime.strftime("%d/%b/%Y")][e.type.name.upcase] = ({} rescue "") if !e.type.nil?
      }

      @patient.encounters.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
          @current_range[0]["START"], @current_range[0]["END"]]).collect{|e| 
        e.observations.each{|o| 
          if o.to_a[0]
            if o.to_a[0].upcase == "DIAGNOSIS" && encounters[e.encounter_datetime.strftime("%d/%b/%Y")][e.type.name.upcase][o.to_a[0].upcase]
              encounters[e.encounter_datetime.strftime("%d/%b/%Y")][e.type.name.upcase][o.to_a[0].upcase] += "; " + o.to_a[1]
            else
              encounters[e.encounter_datetime.strftime("%d/%b/%Y")][e.type.name.upcase][o.to_a[0].upcase] = (o.to_a[1] rescue "") if !e.type.nil?
              if o.to_a[0].upcase == "PLANNED DELIVERY PLACE"
                @current_range[0]["PLANNED DELIVERY PLACE"] = o.to_a[1]
              elsif o.to_a[0].upcase == "MOSQUITO NET"
                @current_range[0]["MOSQUITO NET"] = o.to_a[1]
              end
            end
          end
        }
      }

      @drugs = {}; 
      @other_drugs = {}; 
      main_drugs = ["TTV", "SP", "Fefol", "NVP", "Albendazole", "TDF/3TC/EFV"]
    
      @patient.encounters.find(:all, :order => "encounter_datetime DESC", 
        :conditions => ["encounter_type = ? AND encounter_datetime >= ? AND encounter_datetime <= ?", 
          EncounterType.find_by_name("TREATMENT").id, @current_range[0]["START"], @current_range[0]["END"]]).each{|e| 
        @drugs[e.encounter_datetime.strftime("%d/%b/%Y")] = {} if !@drugs[e.encounter_datetime.strftime("%d/%b/%Y")]; 
        @other_drugs[e.encounter_datetime.strftime("%d/%b/%Y")] = {} if !@other_drugs[e.encounter_datetime.strftime("%d/%b/%Y")]; 
        e.orders.each{|o| 
          if main_drugs.include?(o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")])          
            if o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")] == "NVP"
              if o.drug_order.drug.name.upcase.include?("ML")
                @drugs[e.encounter_datetime.strftime("%d/%b/%Y")][o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")]] = o.drug_order.amount_needed
              else
                @other_drugs[e.encounter_datetime.strftime("%d/%b/%Y")][o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")]] = o.drug_order.amount_needed
              end
            else            
              @drugs[e.encounter_datetime.strftime("%d/%b/%Y")][o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")]] = o.drug_order.amount_needed
            end          
          else
            @other_drugs[e.encounter_datetime.strftime("%d/%b/%Y")][o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")]] = o.drug_order.amount_needed
          end
        }      
      }
    
      label = ZebraPrinter::StandardLabel.new

      label.draw_line(20,25,800,2,0)
      label.draw_line(20,25,2,280,0)
      label.draw_line(20,305,800,2,0)
      label.draw_line(805,25,2,280,0)
      label.draw_text("Visit Summary",28,33,0,1,1,2,false)
      label.draw_text("Last Menstrual Period: #{@current_range[0]["START"].to_date.strftime("%d/%b/%Y") rescue ""}",28,76,0,2,1,1,false)
      label.draw_text("Expected Date of Delivery: #{(@current_range[0]["END"].to_date - 5.week).strftime("%d/%b/%Y") rescue ""}",28,99,0,2,1,1,false)
      label.draw_line(28,60,132,1,0)
      label.draw_line(20,130,800,2,0)
      label.draw_line(20,190,800,2,0)
      label.draw_text("Gest.",29,140,0,2,1,1,false)
      label.draw_text("Fundal",99,140,0,2,1,1,false)
      label.draw_text("Pos./",178,140,0,2,1,1,false)
      label.draw_text("Fetal",259,140,0,2,1,1,false)
      label.draw_text("Weight",339,140,0,2,1,1,false)
      label.draw_text("(kg)",339,158,0,2,1,1,false)
      label.draw_text("BP",435,140,0,2,1,1,false)
      label.draw_text("Urine",499,138,0,2,1,1,false)
      label.draw_text("Prote-",499,156,0,2,1,1,false)
      label.draw_text("in",505,174,0,2,1,1,false)
      label.draw_text("SP",595,140,0,2,1,1,false)
      label.draw_text("(tabs)",575,158,0,2,1,1,false)
      label.draw_text("FeFo",664,140,0,2,1,1,false)
      label.draw_text("(tabs)",655,158,0,2,1,1,false)
      label.draw_text("Albe.",740,140,0,2,1,1,false)
      label.draw_text("(mg)",740,156,0,2,1,1,false)
      label.draw_text("Age",35,158,0,2,1,1,false)
      label.draw_text("Height",99,158,0,2,1,1,false)
      label.draw_text("Pres.",178,158,0,2,1,1,false)
      label.draw_text("Heart",259,158,0,2,1,1,false)
      label.draw_line(90,130,2,175,0)
      label.draw_line(170,130,2,175,0)
      label.draw_line(250,130,2,175,0)
      label.draw_line(330,130,2,175,0)
      label.draw_line(410,130,2,175,0)
      label.draw_line(490,130,2,175,0)
      label.draw_line(570,130,2,175,0)
      label.draw_line(650,130,2,175,0)
      label.draw_line(730,130,2,175,0)
    
      @i = 0

      encounters.sort.each do |encounter|
        @i = @i + 1
      
        if encounter[0] == target_date.to_date.strftime("%d/%b/%Y")
          visit = encounters[encounter[0]]["ANC VISIT TYPE"]["REASON FOR VISIT"].to_i
        
          label.draw_text("Visit No: #{visit}",250,33,0,1,1,2,false)
          label.draw_text("Visit Date: #{encounter[0]}",450,33,0,1,1,2,false)
        
          gest = (((encounter[0].to_date - @current_range[0]["START"].to_date).to_i / 7) <= 0 ? "?" : 
              (((encounter[0].to_date - @current_range[0]["START"].to_date).to_i / 7) - 1).to_s + "wks") rescue ""
            
          label.draw_text(gest,29,200,0,2,1,1,false)
        
          fund = (encounters[encounter[0]]["OBSERVATIONS"]["FUNDUS"].to_i <= 0 ? "?" : 
              encounters[encounter[0]]["OBSERVATIONS"]["FUNDUS"].to_i.to_s + "(wks)") rescue ""
            
          label.draw_text(fund,99,200,0,2,1,1,false)
        
          posi = encounters[encounter[0]]["OBSERVATIONS"]["POSITION"] rescue ""
          pres = encounters[encounter[0]]["OBSERVATIONS"]["PRESENTATION"] rescue ""
        
          posipres = paragraphate(posi.to_s + pres.to_s,5, 5)
        
          (0..(posipres.length)).each{|u|
            label.draw_text(posipres[u],178,(200 + (13 * u)),0,2,1,1,false)
          }
        
          fet = (encounters[encounter[0]]["OBSERVATIONS"]["FETAL HEART BEAT"].humanize == "Unknown" ? "?" :
              encounters[encounter[0]]["OBSERVATIONS"]["FETAL HEART BEAT"].humanize).gsub(/Fetal\smovement\sfelt\s\(fmf\)/i,"FMF") rescue ""
        
          fet = paragraphate(fet, 5, 5)
        
          (0..(fet.length)).each{|f|
            label.draw_text(fet[f],259,(200 + (13 * f)),0,2,1,1,false)
          }
        
          wei = (encounters[encounter[0]]["VITALS"]["WEIGHT (KG)"].to_i <= 0 ? "?" : 
              ((encounters[encounter[0]]["VITALS"]["WEIGHT (KG)"].to_s.match(/\.[1-9]/) ? 
                  encounters[encounter[0]]["VITALS"]["WEIGHT (KG)"] : 
                  encounters[encounter[0]]["VITALS"]["WEIGHT (KG)"].to_i))) rescue ""
        
          label.draw_text(wei,339,200,0,2,1,1,false)
        
          sbp = (encounters[encounter[0]]["VITALS"]["SYSTOLIC BLOOD PRESSURE"].to_i <= 0 ? "?" : 
              encounters[encounter[0]]["VITALS"]["SYSTOLIC BLOOD PRESSURE"].to_i) rescue "?"
            
          dbp = (encounters[encounter[0]]["VITALS"]["DIASTOLIC BLOOD PRESSURE"].to_i <= 0 ? "?" : 
              encounters[encounter[0]]["VITALS"]["DIASTOLIC BLOOD PRESSURE"].to_i) rescue "?"
        
          bp = paragraphate(sbp.to_s + "/" + dbp.to_s, 4, 3)
        
          (0..(bp.length)).each{|u|
            label.draw_text(bp[u],420,(200 + (18 * u)),0,2,1,1,false)
          }
        
          uri = encounters[encounter[0]]["LAB RESULTS"]["URINE PROTEIN"] rescue ""
        
          uri = paragraphate(uri, 5, 5)
        
          (0..(uri.length)).each{|u|
            label.draw_text(uri[u],498,(200 + (18 * u)),0,2,1,1,false)
          }
        
          sp = (@drugs[encounter[0]]["SP"].to_i > 0 ? @drugs[encounter[0]]["SP"].to_i : "") rescue ""
        
          label.draw_text(sp,595,200,0,2,1,1,false)
        
          fefo = (@drugs[encounter[0]]["Fefol"].to_i > 0 ? @drugs[encounter[0]]["Fefol"].to_i : "") rescue ""
        
          label.draw_text(fefo,664,200,0,2,1,1,false)
        
          albe = (@drugs[encounter[0]]["Albendazole"].to_i > 0 ? @drugs[encounter[0]]["Albendazole"].to_i : "") rescue ""
        
          label.draw_text(albe,740,200,0,2,1,1,false)
        end 
      
      end
    
      @encounters = encounters
    
      label.print(1)
    end
  
    def visit_summary2_label(target_date = Date.today)
      @patient = self.patient rescue nil
    
      @current_range = self.active_range(target_date.to_date)

      # raise @current_range.to_yaml
    
      encounters = {}

      @patient.encounters.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
          @current_range[0]["START"], @current_range[0]["END"]]).collect{|e|    
        encounters[e.encounter_datetime.strftime("%d/%b/%Y")] = {"USER" => User.find(e.creator).name}      
      }

      @patient.encounters.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
          @current_range[0]["START"], @current_range[0]["END"]]).collect{|e| 
        encounters[e.encounter_datetime.strftime("%d/%b/%Y")][e.type.name.upcase] = ({} rescue "") if !e.type.nil?
      }

      @patient.encounters.find(:all, :conditions => ["encounter_datetime >= ? AND encounter_datetime <= ?", 
          @current_range[0]["START"], @current_range[0]["END"]]).collect{|e| 
        e.observations.each{|o| 
          if o.to_a[0]
            if o.to_a[0].upcase == "DIAGNOSIS" && encounters[e.encounter_datetime.strftime("%d/%b/%Y")][e.type.name.upcase][o.to_a[0].upcase]
              encounters[e.encounter_datetime.strftime("%d/%b/%Y")][e.type.name.upcase][o.to_a[0].upcase] += "; " + o.to_a[1]
            else
              encounters[e.encounter_datetime.strftime("%d/%b/%Y")][e.type.name.upcase][o.to_a[0].upcase] = (o.to_a[1] rescue "") if !e.type.nil?
              if o.to_a[0].upcase == "PLANNED DELIVERY PLACE"
                @current_range[0]["PLANNED DELIVERY PLACE"] = o.to_a[1]
              elsif o.to_a[0].upcase == "MOSQUITO NET"
                @current_range[0]["MOSQUITO NET"] = o.to_a[1]
              end
            end
          end
        }
      }

      @drugs = {}; 
      @other_drugs = {}; 
      main_drugs = ["TTV", "SP", "Fefol", "NVP", "Albendazole", "TDF/3TC/EFV"]
    
      @patient.encounters.find(:all, :order => "encounter_datetime DESC", 
        :conditions => ["encounter_type = ? AND encounter_datetime >= ? AND encounter_datetime <= ?", 
          EncounterType.find_by_name("TREATMENT").id, @current_range[0]["START"], @current_range[0]["END"]]).each{|e| 
        @drugs[e.encounter_datetime.strftime("%d/%b/%Y")] = {} if !@drugs[e.encounter_datetime.strftime("%d/%b/%Y")]; 
        @other_drugs[e.encounter_datetime.strftime("%d/%b/%Y")] = {} if !@other_drugs[e.encounter_datetime.strftime("%d/%b/%Y")]; 
        e.orders.each{|o| 
          if main_drugs.include?(o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")])          
            if o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")] == "NVP"
              if o.drug_order.drug.name.upcase.include?("ML")
                @drugs[e.encounter_datetime.strftime("%d/%b/%Y")][o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")]] = o.drug_order.amount_needed
              else
                @other_drugs[e.encounter_datetime.strftime("%d/%b/%Y")][o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")]] = o.drug_order.amount_needed
              end
            else            
              @drugs[e.encounter_datetime.strftime("%d/%b/%Y")][o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")]] = o.drug_order.amount_needed
            end          
          else
            @other_drugs[e.encounter_datetime.strftime("%d/%b/%Y")][o.drug_order.drug.name[0, o.drug_order.drug.name.index(" ")]] = o.drug_order.amount_needed
          end
        }      
      }
    
      label = ZebraPrinter::StandardLabel.new

      label.draw_line(20,25,800,2,0)
      label.draw_line(20,25,2,280,0)
      label.draw_line(20,305,800,2,0)
      label.draw_line(805,25,2,280,0)
    
      label.draw_line(20,130,800,2,0)
      label.draw_line(20,190,800,2,0)
    
      label.draw_line(72,130,2,175,0)
      label.draw_line(116,130,2,175,0)
      label.draw_line(156,130,2,175,0)
      label.draw_line(192,130,2,175,0)
      label.draw_line(364,130,2,175,0)
      label.draw_line(594,130,2,175,0)
      label.draw_line(706,130,2,175,0)
      label.draw_text("Planned Delivery Place: #{@current_range[0]["PLANNED DELIVERY PLACE"] rescue ""}",28,66,0,2,1,1,false)
      label.draw_text("Bed Net Given: #{@current_range[0]["MOSQUITO NET"] rescue ""}",28,99,0,2,1,1,false)
      label.draw_text("TDF",28,138,0,2,1,1,false)
      label.draw_text("3TC",28,156,0,2,1,1,false)
      label.draw_text("EFV",28,174,0,2,1,1,false)
      label.draw_text("NVP",78,140,0,2,1,1,false)
      label.draw_text("Baby",77,158,0,1,1,1,false)
      label.draw_text("(ml)",77,176,0,1,1,1,false)
      label.draw_text("On",122,140,0,2,1,1,false)
      label.draw_text("CPT",120,158,0,1,1,1,false)
      label.draw_text("On",162,140,0,2,1,1,false)
      label.draw_text("ART",160,158,0,1,1,1,false)
      label.draw_text("Signs/Symptoms",198,140,0,2,1,1,false)
      label.draw_text("Medication/Outcome",370,140,0,2,1,1,false)
      label.draw_text("Next Vis.",600,140,0,2,1,1,false)
      label.draw_text("Date",622,158,0,2,1,1,false)
      label.draw_text("Provider",710,140,0,2,1,1,false)

      @i = 0

      encounters.sort.each do |encounter|
        @i = @i + 1
      
        if encounter[0] == target_date.to_date.strftime("%d/%b/%Y")
        
          tdf = (@drugs[encounter[0]]["TDF/3TC/EFV"].to_i > 0 ? @drugs[encounter[0]]["TDF/3TC/EFV"].to_i : "") rescue ""
          
          label.draw_text(tdf,28,200,0,2,1,1,false)
        
          nvp = (@drugs[encounter[0]]["NVP"].to_i > 0 ? @drugs[encounter[0]]["NVP"].to_i : "") rescue ""
          
          label.draw_text(nvp,77,200,0,2,1,1,false)
      
          cpt = (encounters[encounter[0]]["LAB RESULTS"]["TAKING CO-TRIMOXAZOLE PREVENTIVE THERAPY"].upcase == "YES" ? "Y" : "N") rescue ""
        
          label.draw_text(cpt,124,200,0,2,1,1,false)
        
          art = (encounters[encounter[0]]["LAB RESULTS"]["ON ART"].upcase == "YES" ? "Y" : "N") rescue ""
        
          label.draw_text(art,164,200,0,2,1,1,false)
        
          sign = encounters[encounter[0]]["OBSERVATIONS"]["DIAGNOSIS"].humanize rescue ""
        
          sign = paragraphate(sign.to_s, 13, 5)
        
          (0..(sign.length)).each{|m|
            label.draw_text(sign[m],198,(200 + (18 * m)),0,2,1,1,false)
          }
        
          med = encounters[encounter[0]]["UPDATE OUTCOME"]["OUTCOME"].humanize + "; " rescue ""
          oth = (@other_drugs[encounter[0]].collect{|d, v| 
              "#{d}: #{ (v.to_s.match(/\.[1-9]/) ? v : v.to_i) }"
            }.join("; ")) if @other_drugs[encounter[0]].length > 0 rescue ""
          
          med = paragraphate(med.to_s + oth.to_s, 17, 5)
        
          (0..(med.length)).each{|m|
            label.draw_text(med[m],370,(200 + (18 * m)),0,2,1,1,false)
          }
        
          nex = encounters[encounter[0]]["APPOINTMENT"]["APPOINTMENT DATE"] rescue []
        
          if nex != []
            date = nex.to_date
            nex = []
            nex << date.strftime("%d/")
            nex << date.strftime("%b/")
            nex << date.strftime("%Y")
          end
        
          (0..(nex.length)).each{|m|
            label.draw_text(nex[m],610,(200 + (18 * m)),0,2,1,1,false)
          }
        
          use = encounters[encounter[0]]["USER"] rescue ""
          
          label.draw_text(use,710,200,0,2,1,1,false)
        
        end
      end
    
      label.print(1)
    end
  
    def abbreviate(string)
      string.strip.split(" ").collect{|e| e[0,1].upcase + "." if e[0,1] != ("(")}.join("")
    end
  
    def truncate(string, length = 6)
      string[0,length] + "."
    end
  
    def paragraphate(string, collen = 8, rows = 2)
      arr = []
    
      if string.nil? 
        return arr
      end
    
      string = string.strip
    
      (0..rows).each{|p| 
        if !(string[p*collen,collen]).nil?
          if p == rows
            arr << (string[p*collen,collen] + ".") if !(string[p*collen,collen]).nil?
          elsif string[((p*collen) + collen),1] != " " && !string.strip[((p+1)*collen),collen].nil? && 
              string[(((p+1)*collen) + collen),1] != " "
            arr << (string[p*collen,collen] + "-") if !(string[p*collen,collen]).nil?
          else 
            arr << string[p*collen,collen] if !(string[p*collen,collen]).nil?
          end
        end
      }
      arr
    end  
        
    def name
      "#{self.person.names.first.given_name} #{self.person.names.first.family_name}".titleize rescue nil
    end  

    def first_name
      "#{self.person.names.first.given_name}".titleize rescue nil
    end

    def last_name
      "#{self.person.names.first.family_name}".titleize rescue nil
    end

    def middle_name
      "#{self.person.names.first.middle_name}".titleize rescue nil
    end

    def maiden_name
      "#{self.person.names.first.family_name2}".titleize rescue nil
    end

    def current_address2
      "#{self.person.addresses.last.city_village}" rescue nil
    end 

    def current_address1
      "#{self.person.addresses.last.address1}" rescue nil
    end

    def current_district
      "#{self.person.addresses.last.state_province}" rescue nil
    end

    def current_address
      "#{self.current_address1}, #{self.current_address2}, #{self.current_district}" rescue nil
    end

    def home_district
      "#{self.person.addresses.last.address2}" rescue nil
    end

    def home_ta
      "#{self.person.addresses.last.county_district}" rescue nil
    end

    def home_village
      "#{self.person.addresses.last.neighborhood_cell}" rescue nil
    end

    def age(today = Date.today)
      return nil if self.person.birthdate.nil?

      # This code which better accounts for leap years
      patient_age = (today.year - self.person.birthdate.year) + ((today.month - self.person.birthdate.month) + ((today.day - self.person.birthdate.day) < 0 ? -1 : 0) < 0 ? -1 : 0)

      # If the birthdate was estimated this year, we round up the age, that way if
      # it is March and the patient says they are 25, they stay 25 (not become 24)
      birth_date=self.person.birthdate
      estimate=self.person.birthdate_estimated==1
      patient_age += (estimate && birth_date.month == 7 && birth_date.day == 1  && 
          today.month < birth_date.month && self.person.date_created.year == today.year) ? 1 : 0
    end

    def age_in_months(today = Date.today)
      years = (today.year - self.person.birthdate.year)
      months = (today.month - self.person.birthdate.month)
      (years * 12) + months
    end

    def age_in_weeks(today = Date.today)
      weeks = (today - self.person.birthdate).to_i / 7
    end

    def age_in_days(today = Date.today)
      days = (today - self.person.birthdate).to_i
    end

    def birthdate_formatted
      if self.person.birthdate_estimated==1
        if self.person.birthdate.day == 1 and self.person.birthdate.month == 7
          self.person.birthdate.strftime("??/???/%Y")
        elsif self.person.birthdate.day == 15 
          self.person.birthdate.strftime("??/%b/%Y")
        elsif self.person.birthdate.day == 1 and self.person.birthdate.month == 1 and self.person.birthdate.year == 1900
          self.person.birthdate.strftime("??/??/????")
        end
      else
        self.person.birthdate.strftime("%d/%b/%Y")
      end
    end

    def self.set_birthdate(person_id, year = nil, month = nil, day = nil)   
      raise "No year passed for estimated birthdate" if year.nil?

      person = Person.find(person_id) rescue nil
      raise "Person not found" if person.nil?
      
      # Handle months by name or number (split this out to a date method)    
      month_i = (month || 0).to_i
      month_i = Date::MONTHNAMES.index(month) if month_i == 0 || month_i.blank?
      month_i = Date::ABBR_MONTHNAMES.index(month) if month_i == 0 || month_i.blank?
    
      if month_i == 0 || month == "Unknown"
        person.birthdate = Date.new(year.to_i,7,1)
        person.birthdate_estimated = 1
      elsif day.blank? || day == "Unknown" || day == 0
        person.birthdate = Date.new(year.to_i,month_i,15)
        person.birthdate_estimated = 1
      else
        person.birthdate = Date.new(year.to_i,month_i,day.to_i)
        person.birthdate_estimated = 0
      end
      person.save
    end

    def self.set_birthdate_by_age(person_id, age, today = Date.today)

      person = Person.find(person_id) rescue nil
      raise "Person not found" if person.nil?
      
      person.birthdate = Date.new(today.year - age.to_i, 7, 1)
      person.birthdate_estimated = 1
      person.save
    end

    def demographics

      if self.person.birthdate_estimated==1
        birth_day = "Unknown"
        if self.person.birthdate.month == 7 and self.person.birthdate.day == 1
          birth_month = "Unknown"
        else
          birth_month = self.person.birthdate.month
        end
      else
        birth_month = self.person.birthdate.month
        birth_day = self.person.birthdate.day
      end

      demographics = {"person" => {
          "date_changed" => self.person.date_changed.to_s,
          "gender" => self.person.gender,
          "birth_year" => self.person.birthdate.year,
          "birth_month" => birth_month,
          "birth_day" => birth_day,
          "names" => {
            "given_name" => self.person.names[0].given_name,
            "family_name" => self.person.names[0].family_name,
            "family_name2" => ""
          },
          "addresses" => {
            "county_district" => "",
            "city_village" => self.person.addresses[0].city_village,
            "location" => self.person.addresses[0].address2
          },
          "occupation" => self.person.get_attribute('Occupation')}}
 
      if not self.person.patient.patient_identifiers.blank? 
        demographics["person"]["patient"] = {"identifiers" => {}}
        self.person.patient.patient_identifiers.each{|identifier|
          demographics["person"]["patient"]["identifiers"][identifier.type.name] = identifier.identifier
        }
      end

      return demographics
    end

    def nationality
      nationality = get_attribute("Citizenship")

      if !nationality.nil? and nationality.downcase == "other"
        nationality = get_attribute("Race")
      end
      
      nationality
    end

    def get_attribute(attribute)
      PersonAttribute.find(:last,:conditions =>["voided = 0 AND person_attribute_type_id = ? AND person_id = ?",
          PersonAttributeType.find_by_name(attribute).id,self.person.id],
        :order => ["date_created ASC"]).value rescue nil
    end

    def get_full_attribute(attribute)
      PersonAttribute.find(:last,:conditions =>["voided = 0 AND person_attribute_type_id = ? AND person_id = ?",
          PersonAttributeType.find_by_name(attribute).id,self.person.id],
        :order => ["date_created ASC"]) rescue nil
    end

    def set_attribute(attribute, value)
      PersonAttribute.create(:person_id => self.person.person_id, :value => value,
        :person_attribute_type_id => (PersonAttributeType.find_by_name(attribute).id))
    end

    def set_identifier(identifier_type, identifier)
      PatientIdentifier.create(:patient_id => self.patient.patient_id, :identifier => identifier,
        :identifier_type => (PatientIdentifierType.find_by_name(identifier_type).id))
    end

    def phone_numbers
      # PersonAttribute.phone_numbers(self.person.person_id)
      home_phone_id       = PersonAttributeType.find_by_name('HOME PHONE NUMBER').person_attribute_type_id
      cell_phone_id       = PersonAttributeType.find_by_name('CELL PHONE NUMBER').person_attribute_type_id
      office_phone_id     = PersonAttributeType.find_by_name('OFFICE PHONE NUMBER').person_attribute_type_id

      phone_number_query  = "SELECT person_attribute_type.name AS attribute_type, person_attribute.value
                            FROM  person_attribute, person_attribute_type
                            WHERE person_attribute_type.person_attribute_type_id = person_attribute.person_attribute_type_id
                            AND   person_attribute.person_attribute_type_id IN (#{home_phone_id}, #{cell_phone_id},#{office_phone_id})
                            AND   person_id = #{self.person.person_id}"

      phone_number_objects = PersonAttribute.find_by_sql(phone_number_query)

      # create a hash of 'symbols' and 'values' like:
      #   {cell_phone_number => '0123456789', home_phone_number => '0987654321'}
      person_phone_numbers = phone_number_objects.reduce({}) do |result, number|
        attribute_type          = number.attribute_type.downcase.gsub(" ", "_").to_sym
        result[attribute_type]  = number.value
        result
      end

      person_phone_numbers
    end

    def sex
      if self.person.gender == "M"
        return "Male"
      elsif self.person.gender == "F"
        return "Female"
      else
        return nil
      end
    end

    def residence
      "#{self.person.addresses.first.city_village}" rescue nil
    end

    def fundus
      self.patient.encounters.collect{|e| 
        e.observations.collect{|o| 
          o.answer_string.to_i if o.concept.concept_names.map(& :name).include?("Fundus")
        }.compact
      }.uniq.delete_if{|x| x == []}.flatten.max
    end

    def fundus_by_lmp(today = Date.today)
      self.patient.encounters.collect{|e|
        e.observations.collect{|o|
          (((today.to_date - o.answer_string.to_date).to_i/7) rescue nil) if o.concept.concept_names.map(& :name).include?("Date of last menstrual period")
        }.compact
      }.uniq.delete_if{|x| x == []}.flatten.max
    end

    def lmp(today = Date.today)
      self.patient.encounters.collect{|e|
        e.observations.collect{|o|
          (o.answer_string.to_date rescue nil) if o.concept.concept_names.map(& :name).include?("Date of last menstrual period") && o.answer_string.to_date <= today.to_date
        }.compact
      }.uniq.delete_if{|x| x == []}.flatten.max
    end

    def gravida(today = Date.today)
      self.patient.encounters.collect{|e|
        e.observations.collect{|o|
          o.answer_string.to_i if o.concept.concept_names.map(& :name).include?("Gravida") && o.obs_datetime.to_date <= today.to_date
        }.compact
      }.uniq.delete_if{|x| x == []}.flatten.max
    end

    def hiv_status
      stat = self.patient.encounters.last(:joins => [:observations], :conditions => 
          ["encounter_type = ? AND obs.concept_id = ? AND ((obs.value_coded IN (?)" + 
            " OR obs.value_text = 'POSITIVE') OR (obs.value_coded IN (?) OR obs.value_text = 'NEGATIVE'))", 
          EncounterType.find_by_name("LAB RESULTS").id, ConceptName.find_by_name("HIV status").concept_id, 
          ConceptName.find(:all, :conditions => ["name = 'POSITIVE'"]).collect{|c| c.concept_id}, 
          ConceptName.find(:all, :conditions => ["name = 'NEGATIVE'"]).collect{|c| 
            c.concept_id}]).observations.collect{|o| o.answer_string.strip if o.answer_string.titleize.squish == "Positive" || 
          o.answer_string.titleize.squish == "Negative"}.compact.last rescue nil

      stat = "Unknown" if stat.nil?
      
      stat
    end
    
    def hiv_status_duration(session_date = Date.today)
      stat = (session_date.to_date - self.patient.encounters.last(:joins => [:observations], :conditions => 
            ["encounter_type = ? AND obs.concept_id = ? AND ((obs.value_coded IN (?)" + 
              " OR obs.value_text = 'POSITIVE') OR (obs.value_coded IN (?) OR obs.value_text = 'NEGATIVE'))", 
            EncounterType.find_by_name("LAB RESULTS").id, ConceptName.find_by_name("HIV status").concept_id, 
            ConceptName.find(:all, :conditions => ["name = 'POSITIVE'"]).collect{|c| c.concept_id}, 
            ConceptName.find(:all, :conditions => ["name = 'NEGATIVE'"]).collect{|c| 
              c.concept_id}]).observations.collect{|o| 
          o.answer_string if o.concept.id == ConceptName.find_by_name("HIV test date").concept_id
        }.compact.last.squish.to_date).to_i / 30.0 rescue 0
    end
    
    def birth_year
      self.person.birthdate.year rescue (Date.today - 13.year).year
    end
    
    def anc_visits(session_date = Date.today)
      self.patient.encounters.all(:conditions => 
          ["DATE(encounter_datetime) >= ? AND DATE(encounter_datetime) <= ? AND encounter_type = ?", 
          (session_date - 6.month), (session_date + 6.month), 
          EncounterType.find_by_name("ANC VISIT TYPE")]).collect{|e| 
        e.observations.collect{|o| 
          o.answer_string.to_i if o.concept.concept_names.first.name.downcase == "reason for visit"
        }.compact
      }.flatten rescue []
    end

    def mother
      m = self.patient.relationships.find(:last, :conditions => ["relationship = ?",
          RelationshipType.find_by_b_is_to_a("Mother").id]) rescue nil

      if !m.blank?
        m = nil if Patient.find(m.person_b).nil?
      end

      m
      
    end

    def father
      f = self.patient.relationships.find(:last, :conditions => ["relationship = ?",
          RelationshipType.find_by_b_is_to_a("Father").id]) rescue nil
      
      if !f.blank?
        f = nil if Patient.find(f.person_b).nil?
      end

      f
      
    end

    def siblings
      Relationship.find(:all, :conditions => ["person_b = ? AND person_a != ?",
          self.mother.relation.id, self.patient.id]) rescue []
    end

    def export_person
      mother = ANCService::ANC.new(self.mother.relation.patient) rescue nil
      father = ANCService::ANC.new(self.father.relation.patient) rescue nil
      {
        "birthdate_estimated" => (self.person.birthdate_estimated rescue nil),
        "gender" => (self.person.gender rescue nil),
        "birthdate" => (self.person.birthdate rescue nil),
        "names" => {
          "given_name" => self.first_name,
          "family_name" => self.last_name
        },
        "patient" => {
          "identifiers" => {
            "diabetes_number" => "",
            "national_id" => self.national_id
          }
        },
        "attributes" => {
          "occupation" => (self.get_full_attribute("Occupation").value rescue nil),
          "cell_phone_number" => (self.get_full_attribute("Cell Phone Number").value rescue nil),
          "citizenship" => (self.get_full_attribute("Citizenship").value rescue nil),
          "race" => (self.get_full_attribute("Race").value rescue nil)
        },
        "addresses" => {
          "address1" => (self.current_address1 rescue nil),
          "city_village" => (self.current_address2 rescue nil),
          "state_province" => (self.current_district rescue nil),
          "address2" => (self.home_district rescue nil),
          "county_district" => (self.home_ta rescue nil),
          "neighborhood_cell" => (self.home_village rescue nil)
        },
        "mother" => {
          "birthdate_estimated" => (mother.person.birthdate_estimated rescue nil),
          "gender" => (mother.person.gender rescue nil),
          "birthdate" => (mother.person.birthdate rescue nil),
          "names" => {
            "given_name" => (mother.first_name rescue nil),
            "family_name" => (mother.last_name rescue nil)
          },
          "patient" => {
            "identifiers" => {
              "diabetes_number" => "",
              "national_id" => (mother.national_id rescue nil)
            }
          },
          "attributes" => {
            "occupation" => (mother.get_full_attribute("Occupation").value rescue nil),
            "cell_phone_number" => (mother.get_full_attribute("Cell Phone Number").value rescue nil),
            "citizenship" => (mother.get_full_attribute("Citizenship").value rescue nil),
            "race" => (mother.get_full_attribute("Race").value rescue nil)
          },
          "addresses" => {
            "address1" => (mother.current_address1 rescue nil),
            "city_village" => (mother.current_address2 rescue nil),
            "address2" => (mother.current_district rescue nil),
            "subregion" => (mother.home_district rescue nil),
            "county_district" => (mother.home_ta rescue nil),
            "neighborhood_cell" => (mother.home_village rescue nil)
          }
        },
        "father" => {
          "birthdate_estimated" => (father.person.birthdate_estimated rescue nil),
          "gender" => (father.person.gender rescue nil),
          "birthdate" => (father.person.birthdate rescue nil),
          "names" => {
            "given_name" => (father.first_name rescue nil),
            "family_name" => (father.last_name rescue nil)
          },
          "patient" => {
            "identifiers" => {
              "diabetes_number" => "",
              "national_id" => (father.national_id rescue nil)
            }
          },
          "attributes" => {
            "occupation" => (father.get_full_attribute("Occupation").value rescue nil),
            "cell_phone_number" => (father.get_full_attribute("Cell Phone Number").value rescue nil),
            "citizenship" => (father.get_full_attribute("Citizenship").value rescue nil),
            "race" => (father.get_full_attribute("Race").value rescue nil)
          },
          "addresses" => {
            "address1" => (father.current_address1 rescue nil),
            "city_village" => (father.current_address2 rescue nil),
            "address2" => (father.current_district rescue nil),
            "subregion" => (father.home_district rescue nil),
            "county_district" => (father.home_ta rescue nil),
            "neighborhood_cell" => (father.home_village rescue nil)
          }
        },
        "facility" => {
          "Health District" => (self.get_full_attribute("Health District").value rescue nil),
          "Health Center" => (self.get_full_attribute("Health Center").value rescue nil),
          "Provider Title" => (self.get_full_attribute("Provider Title").value rescue nil),
          "Hospital Date" => (self.get_full_attribute("Hospital Date").value rescue nil),
          "Provider Name" => (self.get_full_attribute("Provider Name").value rescue nil)
        }
      }
    end

  end

  def self.create_remote(received_params)
    new_params = received_params["person"]
    known_demographics = Hash.new()
    new_params['gender'] == 'F' ? new_params['gender'] = "Female" : new_params['gender'] = "Male"

    known_demographics = {
      "occupation"=>"#{(new_params["attributes"]["occupation"] rescue [])}",
      "education_level"=>"#{(new_params["attributes"]["education_level"] rescue [])}",
      "religion"=>"#{(new_params["attributes"]["religion"] rescue [])}",
      "patient_year"=>"#{new_params["birth_year"]}",
      "patient"=>{
        "gender"=>"#{new_params["gender"]}",
        "birthplace"=>"#{new_params["addresses"]["address2"]}",
        "creator" => 1,
        "changed_by" => 1
      },
      "p_address"=>{
        "identifier"=>"#{new_params["addresses"]["state_province"]}"},
      "home_phone"=>{
        "identifier"=>"#{(new_params["attributes"]["home_phone_number"] rescue [])}"},
      "cell_phone"=>{
        "identifier"=>"#{(new_params["attributes"]["cell_phone_number"] rescue [])}"},
      "office_phone"=>{
        "identifier"=>"#{(new_params["attributes"]["office_phone_number"] rescue [])}"},
      "patient_id"=>"",
      "patient_day"=>"#{new_params["birth_day"]}",
      "patientaddress"=>{"city_village"=>"#{new_params["addresses"]["city_village"]}"},
      "patient_name"=>{
        "family_name"=>"#{new_params["names"]["family_name"]}",
        "given_name"=>"#{new_params["names"]["given_name"]}", "creator" => 1
      },
      "patient_month"=>"#{new_params["birth_month"]}",
      "patient_age"=>{
        "age_estimate"=>"#{new_params["age_estimate"]}"
      },
      "age"=>{
        "identifier"=>""
      },
      "current_ta"=>{
        "identifier"=>"#{new_params["addresses"]["county_district"]}"}
    }

    demographics_params = CGI.unescape(known_demographics.to_param).split('&').map{|elem| elem.split('=')}

    mechanize_browser = Mechanize.new

    demographic_servers = JSON.parse(GlobalProperty.find_by_property("demographic_server_ips_and_local_port").property_value) rescue []

    result = demographic_servers.map{|demographic_server, local_port|

      begin

        output = mechanize_browser.post("http://localhost:#{local_port}/patient/create_remote", demographics_params).body

      rescue Timeout::Error
        return 'timeout'
      rescue
        return 'creationfailed'
      end

      output if output and output.match(/person/)

    }.sort{|a,b|b.length <=> a.length}.first

    result ? JSON.parse(result) : nil
  end

  def self.person_search(params)
    people = search_by_identifier(params[:identifier]) if !params[:identifier].nil?

    return people.first unless people.blank? || people.size > 1

    people = Person.find(:all, :include => [{:names => [:person_name_code]}, :patient], :conditions => [
        "gender = ? AND \
     (person_name.given_name LIKE ? OR person_name_code.given_name_code LIKE ?) AND \
     (person_name.family_name LIKE ? OR person_name_code.family_name_code LIKE ?)",
        params[:gender],
        params[:given_name],
        (params[:given_name] || '').soundex,
        params[:family_name],
        (params[:family_name] || '').soundex
      ]) if people.blank?

    return people
  end

  def self.search_by_identifier(identifier, even_dde = true)
    people = PatientIdentifier.find_all_by_identifier(identifier).map{|id|
      id.patient.person
    } unless identifier.blank? rescue nil
    return people unless people.blank?
    create_from_dde_server = CoreService.get_global_property_value('create.from.dde.server').to_s == "true" rescue false

    if create_from_dde_server && even_dde
      dde_server = GlobalProperty.find_by_property("dde_server_ip").property_value rescue ""
      dde_server_username = GlobalProperty.find_by_property("dde_server_username").property_value rescue ""
      dde_server_password = GlobalProperty.find_by_property("dde_server_password").property_value rescue ""
      uri = "http://#{dde_server_username}:#{dde_server_password}@#{dde_server}/people/find.json"
      uri += "?value=#{identifier}"
      p = JSON.parse(RestClient.get(uri)).first rescue nil

      return [] if p.blank?

      birthdate_year = p["person"]["birthdate"].to_date.year rescue "Unknown"
      birthdate_month = p["person"]["birthdate"].to_date.month rescue nil
      birthdate_day = p["person"]["birthdate"].to_date.day rescue nil
      birthdate_estimated = p["person"]["birthdate_estimated"]
      gender = p["person"]["gender"] == "F" ? "Female" : "Male"

      passed = {
        "person"=>{"occupation"=>p["person"]["data"]["attributes"]["occupation"],
          "age_estimate"=>"",
          "cell_phone_number"=>p["person"]["data"]["attributes"]["cell_phone_number"],
          "birth_month"=> birthdate_month ,
          "addresses"=>{"address1"=>p["person"]["data"]["addresses"]["county_district"],
            "address2"=>p["person"]["data"]["addresses"]["address2"],
            "city_village"=>p["person"]["data"]["addresses"]["city_village"],
            "county_district"=>""},
          "gender"=> gender ,
          "patient"=>{"identifiers"=>{"National id" => p["person"]["value"]}},
          "birth_day"=>birthdate_day,
          "home_phone_number"=>p["person"]["data"]["attributes"]["home_phone_number"],
          "names"=>{"family_name"=>p["person"]["family_name"],
            "given_name"=>p["person"]["given_name"],
            "middle_name"=>""},
          "birth_year"=>birthdate_year},
        "filter_district"=>"Chitipa",
        "filter"=>{"region"=>"Northern Region",
          "t_a"=>""},
        "relation"=>""
      }

      return [self.create_from_form(passed["person"])]
    end
    return people
  end

  def self.update_export_demographics(params, person)

    address_params = params["addresses"]
		names_params = params["names"]
    person_attribute_params = params["attributes"]
		
		params_to_process = params.reject{|key,value| key.match(/addresses|patient|names|relation|cell_phone_number|home_phone_number|office_phone_number|agrees_to_be_visited_for_TB_therapy|agrees_phone_text_for_TB_therapy/) }
		birthday_params = params_to_process.reject{|key,value| key.match(/gender|attributes/) }
		person_params = params_to_process.reject{|key,value| key.match(/birth_|age_estimate|occupation|identifiers|citizenship|race|attributes/) }

		if person_params["gender"].to_s == "Female"
      person_params["gender"] = 'F'
		elsif person_params["gender"].to_s == "Male"
      person_params["gender"] = 'M'
		end

    if !birthday_params.empty?

      if birthday_params["birth_year"] == "Unknown"
        set_birthdate_by_age(person, birthday_params["age_estimate"])
      else
        set_birthdate(person, birthday_params["birth_year"], birthday_params["birth_month"], birthday_params["birth_day"])
      end

      person.birthdate_estimated = 1 if params["birthdate_estimated"] == 'true'
      person.save
    end rescue nil


    person.update_attributes(person_params) if !person_params.empty?
    names_params.delete(:family_name2) if (names_params and names_params[:family_name2].downcase == "unknown" rescue false)
    person.names.first.update_attributes(names_params) if names_params
    person.addresses.first.update_attributes(address_params) if address_params

    #update or add new person attribute
 
    person_attribute_params.each{|attribute_type_name, attribute|
      attribute_type = PersonAttributeType.find_by_name(attribute_type_name.humanize.titleize) || PersonAttributeType.find_by_name("Unknown id")
      #find if attribute already exists
      exists_person_attribute = PersonAttribute.find(:first, :conditions => ["person_id = ? AND person_attribute_type_id = ?", person.id, attribute_type.person_attribute_type_id]) rescue nil
      if exists_person_attribute
        exists_person_attribute.update_attributes({'value' => attribute})
      else
        person.person_attributes.create("value" => attribute, "person_attribute_type_id" => attribute_type.person_attribute_type_id)
      end
    } if person_attribute_params


    
  end
 
	def self.create_from_form(params)

		address_params = params["addresses"]
		names_params = params["names"]
		patient_params = params["patient"]
		params_to_process = params.reject{|key,value| key.match(/addresses|patient|names|relation|cell_phone_number|home_phone_number|office_phone_number|agrees_to_be_visited_for_TB_therapy|agrees_phone_text_for_TB_therapy/) }
		birthday_params = params_to_process.reject{|key,value| key.match(/gender|attributes/) }
		person_params = params_to_process.reject{|key,value| key.match(/birth_|age_estimate|occupation|identifiers|citizenship|race|attributes/) }

		if person_params["gender"].to_s == "Female"
      person_params["gender"] = 'F'
		elsif person_params["gender"].to_s == "Male"
      person_params["gender"] = 'M'
		end

		person = Person.create(person_params)

		if !birthday_params.empty? && birthday_params["birthdate"].blank?      
		  if birthday_params["birth_year"] == "Unknown"
        self.set_birthdate_by_age(person, birthday_params["age_estimate"], person.session_datetime || Date.today)
		  else
        self.set_birthdate(person, birthday_params["birth_year"], birthday_params["birth_month"], birthday_params["birth_day"])
		  end
		end
		person.save

    names_params.delete(:family_name2) if (names_params[:family_name2] and names_params[:family_name2].downcase == "unknown" rescue false)
		person.names.create(names_params)
		person.addresses.create(address_params) unless address_params.empty? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Occupation").person_attribute_type_id,
		  :value => params["occupation"]) unless params["occupation"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Cell Phone Number").person_attribute_type_id,
		  :value => params["cell_phone_number"]) unless params["cell_phone_number"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Office Phone Number").person_attribute_type_id,
		  :value => params["office_phone_number"]) unless params["office_phone_number"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Home Phone Number").person_attribute_type_id,
		  :value => params["home_phone_number"]) unless params["home_phone_number"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Citizenship").person_attribute_type_id,
		  :value => params["citizenship"]) unless params["citizenship"].blank? rescue nil

		person.person_attributes.create(
		  :person_attribute_type_id => PersonAttributeType.find_by_name("Race").person_attribute_type_id,
		  :value => params["race"]) unless params["race"].blank? rescue nil

    # TODO handle the birthplace attribute

		if (!patient_params.nil?)
		  patient = person.create_patient

		  patient_params["identifiers"].each{|identifier_type_name, identifier|
        next if identifier.blank?
        identifier_type_name = (identifier_type_name == "national_id")? "National id" : ((identifier_type_name == "diabetes_number")? "Diabetes Number" : identifier_type_name)
        identifier_type = PatientIdentifierType.find_by_name(identifier_type_name) || PatientIdentifierType.find_by_name("Unknown id")
        patient.patient_identifiers.create("identifier" => identifier, "identifier_type" => identifier_type.patient_identifier_type_id)
		  } if patient_params["identifiers"]

		  # This might actually be a national id, but currently we wouldn't know
		  #patient.patient_identifiers.create("identifier" => patient_params["identifier"], "identifier_type" => PatientIdentifierType.find_by_name("Unknown id")) unless params["identifier"].blank?
		end

		return person
	end

  def self.set_birthdate_by_age(person, age, today = Date.today)
    person.birthdate = Date.new(today.year - age.to_i, 7, 1)
    person.birthdate_estimated = 1
  end

  def self.set_birthdate(person, year = nil, month = nil, day = nil)
    raise "No year passed for estimated birthdate" if year.nil?

    # Handle months by name or number (split this out to a date method)
    month_i = (month || 0).to_i
    month_i = Date::MONTHNAMES.index(month) if month_i == 0 || month_i.blank?
    month_i = Date::ABBR_MONTHNAMES.index(month) if month_i == 0 || month_i.blank?

    if month_i == 0 || month == "Unknown"
      person.birthdate = Date.new(year.to_i,7,1)
      person.birthdate_estimated = 1
    elsif day.blank? || day == "Unknown" || day == 0
      person.birthdate = Date.new(year.to_i,month_i,15)
      person.birthdate_estimated = 1
    else
      person.birthdate = Date.new(year.to_i,month_i,day.to_i)
      person.birthdate_estimated = 0
    end
  end

  def self.update_demographics(params, person=nil)
    person = Person.find(params['person_id']) if person.blank?

    if params.has_key?('person')
      params = params['person']
    end
    
    address_params = params["addresses"]
    names_params = params["names"]
    patient_params = params["patient"]
    person_attribute_params = params["attributes"]

    params_to_process = params.reject{|key,value| key.match(/addresses|patient|names|attributes|cat|action|controller/) }
    birthday_params = params_to_process.reject{|key,value| key.match(/gender|person_id|cat|action|controller/) }

    person_params = params_to_process.reject{|key,value| key.match(/birth_|age_estimate|cat|action|controller/) }

    if !birthday_params.empty?

      if birthday_params["birth_year"] == "Unknown"
        set_birthdate_by_age(person, birthday_params["age_estimate"])
      else
        set_birthdate(person, birthday_params["birth_year"], birthday_params["birth_month"], birthday_params["birth_day"])
      end

      person.birthdate_estimated = 1 if params["birthdate_estimated"] == 'true'
      person.save
    end
  

    person.update_attributes(person_params) if !person_params.empty?
    names_params.delete(:family_name2) if (names_params and names_params[:family_name2].downcase == "unknown" rescue false)
    person.names.first.update_attributes(names_params) if names_params
    person.addresses.first.update_attributes(address_params) if address_params

    #update or add new person attribute
    person_attribute_params.each{|attribute_type_name, attribute|
      attribute_type = PersonAttributeType.find_by_name(attribute_type_name.humanize.titleize) || PersonAttributeType.find_by_name("Unknown id")
      #find if attribute already exists
      exists_person_attribute = PersonAttribute.find(:first, :conditions => ["person_id = ? AND person_attribute_type_id = ?", person.id, attribute_type.person_attribute_type_id]) rescue nil
      if exists_person_attribute
        exists_person_attribute.update_attributes({'value' => attribute})
      else
        person.person_attributes.create("value" => attribute, "person_attribute_type_id" => attribute_type.person_attribute_type_id)
      end
    } if person_attribute_params

    create_from_dde_server = CoreService.get_global_property_value('create.from.dde.server').to_s == "true" rescue false

    if create_from_dde_server
      patient_bean = PatientService.get_patient(person)
      DDEService.update_demographics(patient_bean)
    end

  end

  def self.import_person(person)
    if !person["patient"]["identifiers"]["national_id"].nil? and !person["patient"]["identifiers"]["national_id"].blank?
      child = person.reject{|key,value| key.match(/father|mother|facility/) }

      found_person_data = self.search_by_identifier(child["patient"]["identifiers"]["national_id"])

      found_person = self.create_from_form(child) if found_person_data.nil?

      child_id = nil
      if !found_person_data.nil?
        child_id = found_person_data.last.id
      else
        child_id = found_person.last.id
      end

      found_mother_data = self.search_by_identifier(person["mother"]["patient"]["identifiers"]["national_id"]) rescue nil?
      found_mother = self.create_from_form(person["mother"]) if found_mother_data.nil?

      mother_id = nil
      if !found_mother_data.nil?
        mother_id = found_mother_data.last.id rescue nil
      else
        mother_id = found_mother.last.id rescue nil
      end

      if !mother_id.nil?
        mother_type = RelationshipType.find_by_b_is_to_a("Mother").relationship_type_id

        Relationship.find(:all, :conditions => ["person_a = ? AND relationship = ?",
            child_id, mother_type]).each{|r|
          r.void
        }

        Relationship.create(
          # :creator => User.first.id,
          :person_a => child_id,
          :person_b => mother_id,
          :relationship => mother_type)
      end
      
      found_father_data = self.search_by_identifier(person["father"]["patient"]["identifiers"]["national_id"]) rescue nil?
      found_father = self.create_from_form(person["father"]) if found_father_data.nil?

      father_id = nil
      if !found_father_data.nil?
        father_id = found_father_data.last.id rescue nil
      else
        father_id = found_father.last.id rescue nil
      end

      if !father_id.nil?
        father_type = RelationshipType.find_by_b_is_to_a("Father").relationship_type_id

        Relationship.find(:all, :conditions => ["person_a = ? AND relationship = ?",
            child_id, father_type]).each{|r|
          r.void
        }

        Relationship.create(
          # :creator => User.first.id,
          :person_a => child_id,
          :person_b => father_id,
          :relationship => father_type)

      end

      facility = ["Health Center", "Provider Name", "Provider Title", "Hospital Date", "Health District"]
        
      patient = ANCService::ANC.new(Patient.find(child_id)) rescue nil

      facility.each do|field|
        if !person["facility"][field].nil? && !person["facility"][field].blank?
          patient.set_attribute("#{field}", "#{person["facility"][field]}")
        end
      end

      return "Baby Added"
    end
    return "Baby Not Added"
  end
 
  def self.import_person_no_questions(person)
    if !person["patient"]["identifiers"]["national_id"].nil? and !person["patient"]["identifiers"]["national_id"].blank?
      child = person.reject{|key,value| key.match(/father|mother|facility/) }

      found_person_data = self.search_by_identifier(child["patient"]["identifiers"]["national_id"], false)

      mother = Relationship.find(:first, :order => ["date_created DESC"],
        :conditions => ["person_a =? AND voided = 0 AND relationship = ?",
          found_person_data.last.person_id, RelationshipType.find_by_b_is_to_a("Mother").relationship_type_id]) if !found_person_data.blank?
   
      if mother.present? && (Patient.find(mother.person_b).national_id == person["mother"]["patient"]["identifiers"]["national_id"])
        self.update_export_demographics(person["mother"], Person.find(mother.person_b))
      end
 
      found_person = self.create_from_form(child) if found_person_data.blank?
      
      child_id = nil
      if !found_person_data.blank?
        child_id = found_person_data.last.id
      else
        child_id = found_person.id
      end

      serial_num = PatientIdentifier.find(:first, :order => ["date_created DESC"], :conditions => ["identifier_type = ? AND voided = 0 AND patient_id = ?",
          PatientIdentifierType.find_by_name("Serial Number").id,
          child_id]) rescue nil if child_id.present?

      PatientIdentifier.create(:identifier => child["patient"]["identifiers"]["serial_number"],
        :identifier_type => PatientIdentifierType.find_by_name("Serial Number").id,
        :patient_id => child_id
      ) if serial_num.blank? || (serial_num.present? && serial_num.identifier != child["patient"]["identifiers"]["serial_number"])
                                
      found_mother_data = self.search_by_identifier(person["mother"]["patient"]["identifiers"]["national_id"], false) rescue nil

      found_mother = self.create_from_form(person["mother"]) if found_mother_data.blank?

      mother_id = nil
      if !found_mother_data.blank?
        mother_id = found_mother_data.last.id # rescue nil
      else
        mother_id = found_mother.id # rescue nil
      end
      
      if !mother_id.blank?
        mother_type = RelationshipType.find_by_b_is_to_a("Mother").relationship_type_id
   
        ActiveRecord::Base.transaction do        
         
          if mother.blank? || (mother.present? && Patient.find(mother.person_b).national_id != person["mother"]["patient"]["identifiers"]["national_id"])
           
            Relationship.create(
              {:person_a => child_id,
                :person_b => mother_id,
                :relationship => mother_type})
         
          end
         
        end
        
      end
      
      if !person["father"]["birthdate_estimated"].blank?

        father = Relationship.find(:first, :order => ["date_created DESC"], :conditions => ["person_a =? AND voided = 0 AND relationship = ?",
            child_id, RelationshipType.find_by_b_is_to_a("Father").relationship_type_id]) if child_id.present?

        if father.present? && (Patient.find(father.person_b).national_id == person["father"]["patient"]["identifiers"]["national_id"])
          self.update_export_demographics(person["father"], Person.find(father.person_b))
        end
      
        found_father_data = self.search_by_identifier(person["father"]["patient"]["identifiers"]["national_id"], false) rescue nil
        found_father = self.create_from_form(person["father"]) if found_father_data.blank? &&
          !person["father"]["birthdate_estimated"].blank? rescue nil

        father_id = nil
        if !found_father_data.blank?
          father_id = found_father_data.last.id # rescue nil
        else
          father_id = found_father.id # rescue nil
        end

        if !father_id.blank?
          father_type = RelationshipType.find_by_b_is_to_a("Father").relationship_type_id

          ActiveRecord::Base.transaction do

            if father.blank? || (father.present? && Patient.find(father.person_b).national_id != person["father"]["patient"]["identifiers"]["national_id"])
              Relationship.find(:all, :conditions => ["person_a = ? AND relationship = ?",
                  child_id, father_type]).each{|r|
                r.void
              }

              Relationship.create(
                # :creator => User.first.id,
                :person_a => child_id,
                :person_b => father_id,
                :relationship => father_type)
            end
          end
          
        end
      end
      
      facility = ["Health Center", "Provider Name", "Provider Title", "Hospital Date", "Health District"]

      patient = ANCService::ANC.new(Patient.find(child_id)) rescue nil

      facility.each do|field|
        if !person["facility"][field].nil? && !person["facility"][field].blank?
          patient.get_full_attribute("#{field}").void rescue nil
          patient.set_attribute("#{field}", "#{person["facility"][field]}")
        end
      end

      #******************************Update BirthReportDetail for baby birth report*********************************#
      details = BirthReportDetails.find_by_patient_id(child_id)

      if details.present?
        details.update_attributes(:date_updated => Time.now)
        details.update_attributes(:date_received => Time.now) if details.date_received.blank?
        details.update_attributes(:source => person["facility"]["Health Center"]) if !(person["facility"]["Health Center"]).blank?
      else
        BirthReportDetail.create(:patient_id => child_id,
          :date_created => Time.now,
          :date_received => Time.now,
          :date_updated => Time.now,
          :source => person["facility"]["Health Center"]
        )
      end

      return "Baby Added"
    end
    return "Baby Not Added"
  end

  def self.create_patient_from_dde(params)
    address_params = params["person"]["addresses"]
    names_params = params["person"]["names"]
    patient_params = params["person"]["patient"]
    birthday_params = params["person"]
    params_to_process = params.reject{|key,value|
      key.match(/identifiers|addresses|patient|names|relation|cell_phone_number|home_phone_number|office_phone_number|agrees_to_be_visited_for_TB_therapy|agrees_phone_text_for_TB_therapy/)
    }
    birthday_params = params_to_process["person"].reject{|key,value| key.match(/gender/) }
    person_params = params_to_process["person"].reject{|key,value| key.match(/birth_|age_estimate|occupation/) }


    if person_params["gender"].to_s == "Female"
      person_params["gender"] = 'F'
    elsif person_params["gender"].to_s == "Male"
      person_params["gender"] = 'M'
    end

    unless birthday_params.empty?
      if birthday_params["birth_year"] == "Unknown"
        birthdate = Date.new(Date.today.year - birthday_params["age_estimate"].to_i, 7, 1)
        birthdate_estimated = 1
      else
        year = birthday_params["birth_year"]
        month = birthday_params["birth_month"]
        day = birthday_params["birth_day"]

        month_i = (month || 0).to_i
        month_i = Date::MONTHNAMES.index(month) if month_i == 0 || month_i.blank?
        month_i = Date::ABBR_MONTHNAMES.index(month) if month_i == 0 || month_i.blank?

        if month_i == 0 || month == "Unknown"
          birthdate = Date.new(year.to_i,7,1)
          birthdate_estimated = 1
        elsif day.blank? || day == "Unknown" || day == 0
          birthdate = Date.new(year.to_i,month_i,15)
          birthdate_estimated = 1
        else
          birthdate = Date.new(year.to_i,month_i,day.to_i)
          birthdate_estimated = 0
        end
      end
    else
      birthdate_estimated = 0
    end

    passed_params = {"person"=>
        {"data" =>
          {"addresses"=>
            {"state_province"=> (address_params["state_province"] rescue nil),
            "address2"=> (address_params["address2"] rescue nil),
            "address1"=> (address_params["address1"] rescue nil),
            "neighborhood_cell"=> (address_params["neighborhood_cell"] rescue nil),
            "city_village"=> (address_params["city_village"] rescue nil),
            "county_district"=> (address_params["county_district"] rescue nil)
          },
          "attributes"=>
            {"occupation"=> (params["person"]["occupation"] rescue ""),
            "cell_phone_number" => (params["person"]["cell_phone_number"] rescue ""),
            "citizenship" => (params["person"]["citizenship"] rescue ""),
            "race" => (params["person"]["race"] rescue "")
          },
          "patient"=>
            {"identifiers"=>
              {
              "diabetes_number"=>"",
              "serial_number"=>(patient_params["identifiers"]["serial_number"] rescue "")
            }
          },
          "gender"=> person_params["gender"],
          "birthdate"=> birthdate,
          "birthdate_estimated"=> birthdate_estimated ,
          "names"=>{"family_name"=> names_params["family_name"],
            "given_name"=> names_params["given_name"]
          }}}}
    params[:person][:patient] = Hash.new if params[:person][:patient].blank? and params[:cat] == "baby"
        
    if !params["remote"]

      @dde_server = GlobalProperty.find_by_property("dde_server_ip").property_value rescue ""

      @dde_server_username = GlobalProperty.find_by_property("dde_server_username").property_value rescue ""

      @dde_server_password = GlobalProperty.find_by_property("dde_server_password").property_value rescue ""

      uri = "http://#{@dde_server_username}:#{@dde_server_password}@#{@dde_server}/people.json/"
      recieved_params = RestClient.post(uri,passed_params)

      national_id = JSON.parse(recieved_params)["npid"]["value"]
    else
      national_id = params["person"]["patient"]["identifiers"]["National_id"]
    end

    person = self.create_from_form(params[:person])
    identifier_type = PatientIdentifierType.find_by_name("National id") || PatientIdentifierType.find_by_name("Unknown id")
    person.patient.patient_identifiers.create("identifier" => national_id,
      "identifier_type" => identifier_type.patient_identifier_type_id) unless national_id.blank?

    return person
  end

end
