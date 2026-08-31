# frozen_string_literal: true

# Application-owned policy. The gem neither weakens CSP nor adds inline code.
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.script_src :self
  policy.style_src :self
  policy.img_src :self, :data
  policy.connect_src :self
  policy.object_src :none
  policy.base_uri :self
  policy.form_action :self
end
Rails.application.config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src style-src]
