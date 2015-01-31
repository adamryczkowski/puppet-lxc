module Puppet::Parser::Functions
  newfunction(
    :getuidfn, 
    :type => :rvalue, 
    :doc => "Returns uid for a specified user in args[0]"
  ) do |args|

    # get fact getent_passwd and convert it into hash of user entries
    if args[0].is_a?(String)
      lookupvar("uid_" + args[0])

    else 
      Puppet.warning "getuidfn: usage: getuidfn( user )"
      nil

    end
  end
end

