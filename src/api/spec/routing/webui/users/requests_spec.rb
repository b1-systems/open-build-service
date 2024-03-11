RSpec.describe '/users/:user/requests routes' do
  let(:user) { Faker::Name.first_name }

  it do
    expect(get("/users/#{user}/requests"))
      .to route_to('webui/users/bs_requests#index', user_login: user)
  end
end
