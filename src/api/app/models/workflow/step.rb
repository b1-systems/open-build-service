class Workflow::Step
  include ActiveModel::Model
  include WorkflowStepInstrumentation # for run_callbacks

  SHORT_COMMIT_SHA_LENGTH = 7

  validate :validate_step_instructions

  attr_accessor :scm_webhook, :step_instructions, :token, :workflow_run

  def initialize(attributes = {})
    run_callbacks(:initialize) do
      super
      @step_instructions = attributes[:step_instructions]&.deep_symbolize_keys || {}
    end
  end

  def call
    raise AbstractMethodCalled
  end

  def target_project_name
    return target_project_base_name if scm_webhook.push_event? || scm_webhook.tag_push_event?

    return nil unless scm_webhook.pull_request_event?

    pr_subproject_name = if %w[github gitea].include?(scm_webhook.payload[:scm])
                           scm_webhook.payload[:target_repository_full_name]&.tr('/', ':')
                         else
                           scm_webhook.payload[:path_with_namespace]&.tr('/', ':')
                         end

    "#{target_project_base_name}:#{pr_subproject_name}:PR-#{scm_webhook.payload[:pr_number]}"
  end

  def target_package
    Package.get_by_project_and_name(target_project_name, target_package_name, follow_multibuild: true)
  rescue Project::Errors::UnknownObjectError, Package::Errors::UnknownObjectError
    # We rely on Package.get_by_project_and_name since it's the only way to work with multibuild packages.
    # It's possible for a package to not exist, so we simply rescue and do nothing. The package will be created later in the step.
  end

  def target_package_name(short_commit_sha: false)
    package_name = step_instructions[:target_package] || source_package_name

    case
    when scm_webhook.pull_request_event?
      package_name
    when scm_webhook.push_event?
      commit_sha = scm_webhook.payload[:commit_sha]
      if short_commit_sha
        "#{package_name}-#{commit_sha.slice(0, SHORT_COMMIT_SHA_LENGTH)}"
      else
        "#{package_name}-#{commit_sha}"
      end
    when scm_webhook.tag_push_event?
      "#{package_name}-#{scm_webhook.payload[:tag_name]}"
    end
  end

  protected

  def validate_step_instructions
    self.class::REQUIRED_KEYS.each do |required_key|
      unless step_instructions.key?(required_key)
        errors.add(:base, "The '#{required_key}' key is missing")
        next
      end

      errors.add(:base, "The '#{required_key}' key must provide a value") if step_instructions[required_key].blank?
    end
  end

  def source_package_name
    step_instructions[:source_package]
  end

  def source_project_name
    step_instructions[:source_project]
  end

  private

  def target_project_base_name
    raise AbstractMethodCalled
  end

  def remote_source?
    Project.find_remote_project(source_project_name).present?
  end

  # Only used in LinkPackageStep and BranchPackageStep.
  def validate_source_project_and_package_name
    errors.add(:base, "invalid source project '#{source_project_name}'") if step_instructions[:source_project] && !Project.valid_name?(source_project_name)
    errors.add(:base, "invalid source package '#{source_package_name}'") if step_instructions[:source_package] && !Package.valid_name?(source_package_name)
    errors.add(:base, "invalid target project '#{step_instructions[:target_project]}'") if step_instructions[:target_project] && !Project.valid_name?(step_instructions[:target_project])
  end

  def validate_project_and_package_name
    errors.add(:base, "invalid project '#{step_instructions[:project]}'") if step_instructions[:project] && !Project.valid_name?(step_instructions[:project])
    errors.add(:base, "invalid package '#{step_instructions[:package]}'") if step_instructions[:package] && !Package.valid_name?(step_instructions[:package])
  end
end
