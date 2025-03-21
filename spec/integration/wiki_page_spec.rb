# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require "nokogiri"

describe WikiPagesController do
  before do
    course_with_teacher_logged_in(active_all: true)
  end

  def create_page(attrs)
    page = @course.wiki_pages.create!(attrs)
    page.publish! if page.unpublished?
    page
  end

  it "still works with periods in titles for new pages" do
    course_with_teacher_logged_in(active_all: true, user: user_with_pseudonym)

    get "/courses/#{@course.id}/pages/windurs%203.won/edit?titleize=1"
    expect(response).to be_successful
  end

  it "does not render wiki page body at all if it was deleted" do
    @wiki_page = create_page title: "Some random wiki page",
                             body: "this is the content of the wikipage body asdfasdf"
    @wiki_page.destroy
    get course_wiki_page_url(@course, @wiki_page)
    expect(response.body).not_to include(@wiki_page.body)
  end

  it "links correctly in the breadcrumbs for group wikis" do
    course_with_teacher_logged_in(active_all: true, user: user_with_pseudonym)
    group_category = @course.group_categories.build(name: "mygroup")
    @group = Group.create!(name: "group1", group_category:, context: @course)
    @wiki_page = @group.wiki_pages.create title: "hello", body: "This is a wiki page."

    def test_page(url)
      get url
      expect(response).to be_successful

      html = Nokogiri::HTML5(response.body)
      html.css("#breadcrumbs a").each do |link|
        href = link.attr("href")
        next if href == "/"

        expect(href).to match %r{/groups/#{@group.id}}
      end
    end

    test_page("/groups/#{@group.id}/#{@group.wiki.path}/hello")
    test_page("/groups/#{@group.id}/#{@group.wiki.path}/hello/revisions")
  end

  it "works with account group wiki pages" do
    group = Account.default.groups.create!
    group.add_user(@user)
    group_page = group.wiki_pages.create!(title: "ponies5ever", body: "")

    get "/groups/#{group.id}/pages/#{group_page.url}"
    expect(response).to be_successful
  end

  context "draft state forwarding" do
    before do
      @wiki_page = create_page title: "a-page", body: "body"
      @base_url = "/courses/#{@course.id}/"
      @course.reload
    end

    it "forwards /wiki to /pages index if no front page" do
      @course.wiki.has_no_front_page = true
      @course.wiki.save!
      get @base_url + "wiki"
      expect(response).to redirect_to(course_wiki_pages_url(@course))
    end

    it "renders /wiki as the front page if there is one" do
      @wiki_page.set_as_front_page!
      get @base_url + "wiki"
      expect(response).to be_successful
      expect(assigns[:page]).to eq @wiki_page
    end

    it "forwards /wiki/name to /pages/name" do
      get @base_url + "wiki/a-page"
      expect(response).to redirect_to(course_wiki_page_url(@course, "a-page"))
    end

    it "forwards module_item_id parameter" do
      get @base_url + "wiki/a-page?module_item_id=123"
      expect(response).to redirect_to(course_wiki_page_url(@course, "a-page") + "?module_item_id=123")
    end

    it "forwards /wiki/name/revisions to /pages/name/revisions" do
      get @base_url + "wiki/a-page/revisions"
      expect(response).to redirect_to(course_wiki_page_revisions_url(@course, "a-page"))
    end

    it "forwards /wiki/name/revisions/revision to /pages/name/revisions" do
      get @base_url + "wiki/a-page/revisions/42"
      expect(response).to redirect_to(course_wiki_page_revisions_url(@course, "a-page"))
    end
  end
end

describe "Admin without Course Content - view permission" do
  before do
    course_with_teacher_logged_in(active_all: true)
  end

  it "cannot view unpublished wiki pages" do
    account = @course.root_account
    role = custom_account_role("CustomAccountUser", account:)
    RoleOverride.manage_role_override(account, role, :read_course_content, enabled: false)
    admin = account_admin_user(account:, role:, active_all: true)
    user_session(admin)

    wiki_page = @course.wiki_pages.create!(title: "Unpublished Page", body: "This page should not be viewable", workflow_state: "unpublished")
    get course_wiki_page_url(@course, wiki_page)
    expect(response).to have_http_status(:unauthorized)
  end
end
