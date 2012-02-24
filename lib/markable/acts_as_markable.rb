module Markable
  module ActsAsMarkable
    extend ActiveSupport::Concern

    included do |a|
    end

    module ClassMethods
      def markable_as(marks, options = {})
        Markable.set_models

        cattr_accessor :markable_marks, :instance_writer => false

        marks = Array.wrap(marks)
        raise Markable::WrongMarkType unless marks.all?{ |mark| mark.kind_of? Symbol}

        markers = options[:by].present? ? Array.wrap(options[:by]) : :all

        self.markable_marks ||= {}
        marks.each { |mark|
          self.markable_marks[mark] = {
            :allowed_markers => markers
          }
        }

        class_eval {
          has_many :markable_marks, :class_name => 'Markable::Mark', :as => :markable
          include Markable::ActsAsMarkable::MarkableInstanceMethods

          def self.marked_as mark, options = {}
            if options[:by].present?
              result = self.joins(:markable_marks).where( :marks => { :mark => mark, :marker_id => options[:by].id, :marker_type => options[:by].class.name } )
              markable = self
              result.class_eval do
                define_method :<< do |object|
                  if Array.wrap(object).all?{ |i| i.kind_of?(markable) }
                    options[:by].set_mark mark, object
                  else
                    raise Markable::WrongMarkableType.new
                  end
                  self
                end
                define_method :delete do |markable|
                  options[:by].remove_mark mark, markable
                  self
                end
              end
            else
              result = self.joins(:markable_marks).where( :marks => { :mark => mark } )
            end
            result
          end
        }

        self.markable_marks.each { |mark, o|
          class_eval %(
            def self.marked_as_#{mark} options = {}
              self.marked_as :#{mark}, options
            end

            def marked_as_#{mark}? options = {}
              self.marked_as? :#{mark}, options
            end
          )
        }

        Markable.add_markable self
      end
    end

    module MarkableInstanceMethods
      def mark_as(mark, markers)
        Array.wrap(markers).each { |marker|
          Markable.can_mark_or_raise? marker, self, mark
          params = {
            :markable_id => self.id,
            :markable_type => self.class.name,
            :marker_id => marker.id,
            :marker_type => marker.class.name,
            :mark => mark
          }
          Markable::Mark.create( params ) unless Markable::Mark.exists?( params )
        }
      end

      def marked_as?(mark, options = {})
        if options[:by].present?
          Markable.can_mark_or_raise? options[:by], self, mark
        end
        params = {
          :markable_id => self.id,
          :markable_type => self.class.name,
          :mark => mark
        }
        if options[:by].present?
          params[:marker_id] = options[:by].id
          params[:marker_type] = options[:by].class.name
        end
        Markable::Mark.exists?( params )
      end

      def unmark mark, options = {}
        if options[:by].present?
          Markable.can_mark_or_raise? options[:by], self, mark
          Array.wrap(options[:by]).each { |marker|
            params = {
              :markable_id => self.id,
              :markable_type => self.class.name,
              :marker_id => marker.id,
              :marker_type => marker.class.name,
              :mark => mark
            }
            Markable::Mark.delete_all(params)
          }
        else
          params = {
            :markable_id => self.id,
            :markable_type => self.class.name,
            :mark => mark
          }
          Markable::Mark.delete_all(params)
        end
      end

      def have_marked_as_by(mark, target)
        result = target.joins(:marker_marks).where( :marks => { :mark => mark, :markable_id => self.id, :markable_type => self.class.name } )
        markable = self
        result.class_eval do
          define_method :<< do |markers|
            Array.wrap(markers).each { |marker|
              marker.set_mark mark, markable
            }
            self
          end
          define_method :delete do |markers|
            Markable.can_mark_or_raise? markers, markable, mark
            Array.wrap(markers).each { |marker|
              marker.remove_mark mark, markable
            }
            self
          end
        end
        result
      end
    end
  end
end

ActiveRecord::Base.send :include, Markable::ActsAsMarkable
