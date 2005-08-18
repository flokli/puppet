#!/usr/local/bin/ruby -w

# $Id$

# included so we can test object types
require 'puppet'
require 'puppet/type'

module Puppet
    # events are transient packets of information; they result in one or more (or none)
    # subscriptions getting triggered, and then they get cleared
    # eventually, these will be passed on to some central event system
	class Event
        include Puppet
        # subscriptions are permanent associations determining how different
        # objects react to an event
        class Subscription
            include Puppet
            attr_accessor :source, :event, :target

            def initialize(hash)
                @triggered = false

                hash.each { |param,value|
                    # assign each value appropriately
                    # this is probably wicked-slow
                    self.send(param.to_s + "=",value)
                }
                #Puppet.debug "New Subscription: '%s' => '%s'" %
                #    [@source,@event]
            end

            # the transaction is passed in so that we can notify it if
            # something fails
            def trigger(transaction)
                # this is potentially incomplete, because refreshing an object
                # could theoretically kick off an event, which would not get run
                # or, because we're executing the first subscription rather than
                # the last, a later-refreshed object could somehow be connected
                # to the "old" object rather than "new"
                # but we're pretty far from that being a problem
                event = nil

                if @event == :NONE
                    # just ignore these subscriptions
                    return
                end

                if transaction.triggercount(self) > 0
                    Puppet.debug "%s has already run" % self
                else
                    Puppet.debug "'%s' matched '%s'; triggering '%s' on '%s'" %
                        [@source,@event,@method,@target]
                    begin
                        if @target.respond_to?(@method)
                            event = @target.send(@method)
                        else
                            Puppet.debug "'%s' of type '%s' does not respond to '%s'" %
                                [@target,@target.class,@method.inspect]
                        end
                    rescue => detail
                        # um, what the heck do i do when an object fails to refresh?
                        # shouldn't that result in the transaction rolling back?
                        # the 'onerror' metaparam will be used to determine
                        # behaviour in that case
                        Puppet.err "'%s' failed to %s: '%s'" %
                            [@target,@method,detail]
                        raise
                        #raise "We need to roll '%s' transaction back" %
                            #transaction
                    end
                    transaction.triggered(self)
                end
                return event
            end
        end

		attr_accessor :event, :source, :transaction

        @@events = []

        @@subscriptions = []

        # I think this method is obsolete
        def self.process
            Puppet.debug "Processing events"
            @@events.each { |event|
                @@subscriptions.find_all { |sub|
                    #debug "Sub source: '%s'; event object: '%s'" %
                    #    [sub.source.inspect,event.object.inspect]
                    sub.source == event.object and
                        (sub.event == event.event or
                         sub.event == :ALL_EVENTS)
                }.each { |sub|
                    Puppet.debug "Found subscription to %s" % event
                    sub.trigger(event.transaction)
                }
            }

            @@events.clear
        end

        # I think this method is obsolete
        def self.subscribe(hash)
            if hash[:event] == '*'
                hash[:event] = :ALL_EVENTS
            end
            sub = Subscription.new(hash)

            # add to the correct area
            @@subscriptions.push sub
        end

		def initialize(args)
            unless args.include?(:event) and args.include?(:source)
				raise Puppet::DevError, "Event.new called incorrectly"
			end

			@change = args[:change]
			@event = args[:event]
			@source = args[:source]
			@transaction = args[:transaction]

            #Puppet.info "%s: %s(%s)" %
            #Puppet.info "%s: %s changed from %s to %s" %
            #    [@object,@state.name, @state.is,@state.should]

            # initially, just stuff all instances into a central bucket
            # to be handled as a batch
            #@@events.push self
		end

        def to_s
            self.event.to_s
        end
	end
end


