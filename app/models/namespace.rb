# == Schema Information
#
# Table name: namespaces
#
#  id          :integer          not null, primary key
#  name        :string(255)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  team_id     :integer
#  public      :boolean          default("0")
#  registry_id :integer          not null
#  global      :boolean          default("0")
#  description :text(65535)
#
# Indexes
#
#  fulltext_index_namespaces_on_name         (name)
#  index_namespaces_on_name_and_registry_id  (name,registry_id) UNIQUE
#  index_namespaces_on_registry_id           (registry_id)
#  index_namespaces_on_team_id               (team_id)
#

class Namespace < ActiveRecord::Base
  include PublicActivity::Common

  # This regexp is extracted from the reference package of Docker Distribution
  # and it matches a valid namespace name.
  NAME_REGEXP = /\A[a-z0-9]+(?:[._\\-][a-z0-9]+)*\Z/

  # The maximum length of a namespace name.
  MAX_NAME_LENGTH = 255

  has_many :webhooks
  has_many :repositories
  belongs_to :registry
  belongs_to :team

  validates :public, inclusion: { in: [true] }, if: :global?
  validates :name,
            presence:   true,
            uniqueness: { scope: "registry_id" },
            length:     { maximum: MAX_NAME_LENGTH },
            namespace:  true

  # From the given repository name that can be prefix by the name of the
  # namespace, returns two values:
  #   1. The namespace where the given repository belongs to.
  #   2. The name of the repository itself.
  # If a registry is provided, it will query it for the given repository name.
  def self.get_from_name(name, registry = nil)
    if name.include?("/")
      namespace, name = name.split("/", 2)
      if registry.nil?
        namespace = Namespace.find_by(name: namespace)
      else
        namespace = registry.namespaces.find_by(name: namespace)
      end
    else
      if registry.nil?
        namespace = Namespace.find_by(global: true)
      else
        namespace = Namespace.find_by(registry: registry, global: true)
      end
    end
    [namespace, name, registry]
  end

  # Tries to transform the given name to a valid namespace name. If the name is
  # already valid, then it's returned untouched. Otherwise, if the name cannot
  # be turned into a valid namespace name, then nil is returned.
  def self.make_valid(name)
    return name if name =~ NAME_REGEXP

    # First of all we strip extra characters from the beginning and end.
    first = name.index(/[a-z0-9]/)
    return nil if first.nil?
    last = name.rindex(/[a-z0-9]/)
    str = name[first..last]

    # Replace weird characters with underscores.
    str = str.gsub(/[^[a-z0-9\\.\\-_]]/, "_")

    # Only one special character is allowed in between of alphanumeric
    # characters. Thus, let's merge multiple appearences into one on each case.
    # After that, the name should be fine, so let's trim it if it's too large.
    final = str.gsub(/[._\\-]{2,}/, "_")
    name = final[0..MAX_NAME_LENGTH]

    return nil if name !~ NAME_REGEXP
    name
  end

  # Returns a String containing the cleaned name for this namespace. The
  # cleaned name will be the registry's hostname if this is a global namespace,
  # or the name of the namespace itself otherwise.
  def clean_name
    global? ? registry.hostname : name
  end
end
