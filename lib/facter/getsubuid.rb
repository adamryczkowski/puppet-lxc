# getent.rb
# Tue Dec 18 13:53:39 PST 2012
# agould@ucop.edu


require 'facter'

# Returns passwd entry for all users using "getent".
Facter.add(:getsubuid) do
  users = ''
  %x{cat /etc/subuid}.lines.each do |n|
     users << n.chomp+'|'
  end
  setcode do
      users
  end
end

# Returns groups entry for all groups using "getent".
Facter.add(:getsubgid) do
  groups = ''
  %x{cat /etc/subgid}.lines.each do |n|
     groups << n.chomp+'|'
  end
  setcode do
      groups
  end
end
