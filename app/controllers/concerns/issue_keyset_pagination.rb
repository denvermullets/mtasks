# Keyset pagination on (updated_at, id) for the API issue index.
module IssueKeysetPagination
  extend ActiveSupport::Concern

  DEFAULT_PAGE_LIMIT = 200
  MAX_PAGE_LIMIT = 500

  private

  def paginated?
    params.key?(:limit) || params.key?(:after_id)
  end

  def page_limit
    requested = params[:limit].to_i
    requested = DEFAULT_PAGE_LIMIT unless requested.positive?
    [requested, MAX_PAGE_LIMIT].min
  end

  # Keyset on (updated_at, id). Fetches one extra row so trim_page can tell whether more remain.
  def paginate_scope(scope)
    return scope unless paginated?

    scope = scope.reorder(updated_at: :asc, id: :asc)
    if params.key?(:after_id)
      cursor = current_team.issues.find_by(id: params[:after_id])
      return render_validation_message('after_id must be an issue id in this team') unless cursor

      scope = scope.where('(issues.updated_at, issues.id) > (?, ?)', cursor.updated_at, cursor.id)
    end
    scope.limit(page_limit + 1)
  end

  def trim_page(issues)
    return issues unless paginated? && issues.size > page_limit

    page = issues.first(page_limit)
    response.set_header('X-Next-After-Id', page.last.id.to_s)
    page
  end
end
