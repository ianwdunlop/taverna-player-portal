module Authorization

  # Assumes including class has a "user" attribute

  PRIVILEGES = {
      view: 1,
      edit: 2
  }

  ## Gets a list of privileges from a bitmask
  def self.to_permissions(mask)
    Authorization::PRIVILEGES.select { |_, index| mask & (2 ** (index - 1)) == index }.keys
  end

  ## Turns a list of privileges (or a singleton) into a bitmask
  def self.to_mask(permissions)
    permissions = [permissions] if permissions.is_a?(Symbol)
    permissions.inject(0) { |mask, permission| mask + (2 ** ((Authorization::PRIVILEGES[permission] || 0) - 1) || 0) }
  end

  def self.included(base)
    base.class_eval do
      # Find only things that the given user has the given privilege for
      scope :with_permissions, lambda { |user, privileges|
        mask = Authorization.to_mask(privileges)
        joins("LEFT OUTER JOIN 'policies' ON 'policies'.'id' = '#{self.table_name}'.'policy_id'
               LEFT OUTER JOIN 'permissions' ON 'permissions'.'policy_id' = 'policies'.'id'").
        where("(#{self.table_name}.user_id #{(user.nil? ? 'IS NULL' : '= :user')}) OR
               (permissions.mask & :mask = :mask AND permissions.subject_type = 'User' AND permissions.subject_id = :user) OR
               (permissions.mask & :mask = :mask AND permissions.subject_type = 'Group' AND permissions.subject_id IN (:groups)) OR
               (policies.public_mask & :mask = :mask)",
              mask: mask,
              user: user,
              groups: user.try(:groups) || []).references(:policy, :permissions)
      }

      scope :visible_by, lambda { |user| with_permissions(user, :view) }

      belongs_to :policy, dependent: :destroy

      accepts_nested_attributes_for :policy

      before_validation :ensure_policy
    end
  end

  # Check if the given user has the given privilege.
  # Doesn't need to do additional queries if operating on a #with_privilege scope.
  def can?(user, action)
    (user && user.admin?) ||
    self.user == user ||
    self.policy.permits?(user, action)
  end

  private

  def self.privilege_for_action(action)
    case action.to_sym
      when :new, :create
        :none
      when :view, :show, :index, :download
        :view
      when :edit, :update, :manage, :destroy
        :edit
      else
        raise 'Unrecognized action'
    end
  end

  def ensure_policy
    self.policy ||= default_policy
  end

  def default_policy
    Policy.new(title: 'Default Public Policy', public_permissions: [:view])
  end

end
