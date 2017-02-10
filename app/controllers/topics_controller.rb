# == Schema Information
#
# Table name: topics
#
#  id               :integer          not null, primary key
#  forum_id         :integer
#  user_id          :integer
#  user_name        :string
#  name             :string
#  posts_count      :integer          default(0), not null
#  waiting_on       :string           default("admin"), not null
#  last_post_date   :datetime
#  closed_date      :datetime
#  last_post_id     :integer
#  current_status   :string           default("new"), not null
#  private          :boolean          default(FALSE)
#  assigned_user_id :integer
#  cheatsheet       :boolean          default(FALSE)
#  points           :integer          default(0)
#  post_cache       :text
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  locale           :string
#  doc_id           :integer          default(0)
#  channel          :string           default("email")
#

class TopicsController < ApplicationController

  before_action :authenticate_user!, :only => ['tickets']
  before_action :allow_iframe_requests
  before_action :forums_enabled?, only: ['index','show']
  before_action :topic_creation_enabled?, only: ['new', 'create']
  before_action :get_all_teams, only: 'new'
  before_action :get_public_forums, only: ['new', 'create']

  layout "clean", only: [:new, :index, :thanks]
  theme :theme_chosen

  # TODO Still need to so a lot of refactoring here!

  def index
    @forum = Forum.ispublic.where(id: params[:forum_id]).first
    if @forum
      if @forum.allow_topic_voting == true
        @topics = @forum.topics.ispublic.by_popularity.page params[:page]
      else
        @topics = @forum.topics.ispublic.chronologic.page params[:page]
      end
      @page_title = @forum.name
      add_breadcrumb t(:community, default: "Community"), forums_path
      add_breadcrumb @forum.name
    end
    respond_to do |format|
      format.html {
        redirect_to root_path unless @forum
      }
    end
  end

  def tickets
    @topics = current_user.topics.isprivate.undeleted.chronologic.page params[:page]
    @page_title = t(:tickets, default: 'Tickets')
    add_breadcrumb @page_title
    respond_to do |format|
      format.html # index.rhtml
    end
  end

  def ticket
    if topic_id?
      @topic = current_user.topics.undeleted.where(id: params[:id]).first
    else
      @topic = Topic.where(code: params[:id]).first
      @access_by_code = true if @topic
      flash.now[:info] = I18n.t(:ticket_secret_url_notice, default: "Secret link %{url}", url: request.url)
    end
    if @topic
      @posts = @topic.posts.ispublic.chronologic.active.all.includes(:topic, :user, :screenshot_files)
      @page_title = "##{@topic.id} #{@topic.name}"
      add_breadcrumb t(:tickets, default: 'Tickets'), tickets_path
      add_breadcrumb @page_title
    end
    respond_to do |format|
      format.html {
        redirect_to root_path unless @topic
      }
    end
  end

  def new
    @page_title = t(:get_help_button, default: "Open a ticket")
    @topic = Topic.new
    unless user_signed_in?
      @user = AutoUser.new
    end
    @topic.posts.build
    add_breadcrumb @page_title
  end

  def create
    params[:id].nil? ? @forum = Forum.find(params[:topic][:forum_id]) : @forum = Forum.find(params[:id])

    @topic = @forum.topics.new(
      name: params[:topic][:name],
      private: params[:topic][:private],
      doc_id: params[:topic][:doc_id],
      team_list: params[:topic][:team_list],
      channel: 'web')

    if recaptcha_enabled?
      render :new && return unless verify_recaptcha(model: @topic)
    end

    if @topic.create_topic_with_user(params, current_user)
      @user = @topic.user
      @post = @topic.posts.create(
        :body => params[:topic][:posts_attributes]["0"][:body],
        :user_id => @user.id,
        :kind => 'first',
        :screenshots => params[:topic][:screenshots],
        :attachments => params[:topic][:posts_attributes]["0"][:attachments])

      if !user_signed_in? && @user.email_valid?
        UserMailer.new_user(@user.id, @user.reset_password_token).deliver_later
      end

      # track event in GA
      tracker('Request', 'Post', 'New Topic')
      tracker('Agent: Unassigned', 'New', @topic.to_param)

      if @topic.private?
        redirect_to ticket_path(@topic.code)
      else
        redirect_to topic_posts_path(@topic)
      end
    else
      flash.now[:danger] = @topic.user.errors.full_messages
      @user = @topic.user
      render 'new'
    end
  end

  def thanks
     @page_title = t(:thank_you, default: 'Thank You!')
  end

  def up_vote
    if user_signed_in?
      @topic = Topic.find(params[:id])
      @forum = @topic.forum
      @topic.votes.create(user_id: current_user.id)
      @topic.touch
      @topic.reload
    end
    respond_to do |format|
      format.js
    end
  end

  def tag
    @topics = Topic.ispublic.tag_counts_on(:tags)
  end

  private

  def post_params
    params.require(:post).permit(
      :body,
      :kind,
      {attachments: []}
    )
  end

  def get_public_forums
    @forums = Forum.ispublic.all
  end

  #
  # returns true if params[:id] is a topic id, false
  # otherwise.
  #
  def topic_id?
    param_id = params[:id]
    if param_id.nil?
      true
    elsif param_id =~ /-/
      int = param_id.split('-').first
      int.to_i.to_s == int
    else
      param_id.to_i.to_s == param_id.to_s
    end
  end
end
