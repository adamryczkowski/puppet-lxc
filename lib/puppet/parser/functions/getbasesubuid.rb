module Puppet::Parser::Functions
  newfunction(
    :getbasesubuid, 
    :type => :rvalue, 
    :doc => "Returns base subuid for a user specified in args[0]"
  ) do |args|

    # get fact getent_passwd and convert it into hash of user entries
    subuids={}
    entires = lookupvar('getsubuid').split('|')
    entires.each do |item|
      user,baseuid,cntuid = item.split(':')
      subuids[user] = baseuid ? baseuid : ""
    end

    # make sure args[0] is a strings
    if args[0].is_a?(String)
      subuids[args[0]]

    else 
      Puppet.warning "getbasesubuid: usage: getbasesubuid( user )"
      nil

    end
  end

  newfunction(
    :getcntsubuid, 
    :type => :rvalue, 
    :doc => "Returns number of subuids for user specified in args[0]"
  ) do |args|

    # get fact getent_passwd and convert it into hash of user entries
    subuids={}
    entires = lookupvar('getsubuid').split('|')
    entires.each do |item|
      user,baseuid,cntuid = item.split(':')
      subuids[user] = cntuid ? cntuid : ""
    end

    # make sure args[0] is a strings
    if args[0].is_a?(String)
      subuids[args[0]]

    else 
      Puppet.warning "getcntsubuid: usage: getcntsubuid( user )"
      nil

    end
  end

  newfunction(
    :getbasesubgid, 
    :type => :rvalue, 
    :doc => "Returns base subgid for a user specified in args[0]"
  ) do |args|

    # get fact getent_passwd and convert it into hash of user entries
    subgids={}
    entires = lookupvar('getsubgid').split('|')
    entires.each do |item|
      user,baseuid,cntuid = item.split(':')
      subgids[user] = baseuid ? baseuid : ""
    end

    # make sure args[0] is a strings
    if args[0].is_a?(String)
      subgids[args[0]]

    else 
      Puppet.warning "getbasesubgid: usage: getbasesubgid( user )"
      nil

    end
  end

  newfunction(
    :getcntsubgid, 
    :type => :rvalue, 
    :doc => "Returns number of subgids for user specified in args[0]"
  ) do |args|

    # get fact getent_passwd and convert it into hash of user entries
    subgids={}
    entires = lookupvar('getsubgid').split('|')
    entires.each do |item|
      user,baseuid,cntuid = item.split(':')
      subgids[user] = cntuid ? cntuid : ""
    end

    # make sure args[0] is a strings
    if args[0].is_a?(String)
      subgids[args[0]]

    else 
      Puppet.warning "getcntsubgid: usage: getcntsubgid( user )"
      nil

    end
  end

end

