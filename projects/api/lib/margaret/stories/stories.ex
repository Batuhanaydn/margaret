defmodule Margaret.Stories do
  @moduledoc """
  The Stories context.
  """

  import Ecto.Query
  alias Ecto.Multi

  alias Margaret.{Repo, Accounts, Stories, Publications, Tags}
  alias Accounts.User
  alias Stories.Story

  @doc """
  Gets a single story by its id.

  ## Examples

      iex> get_story(123)
      %Story{}

      iex> get_story(456)
      nil

  """
  @spec get_story(String.t() | non_neg_integer) :: Story.t() | nil
  def get_story(id), do: Repo.get(Story, id)

  @doc """
  Gets a single story by its id.

  Raises `Ecto.NoResultsError` if the Story does not exist.

  ## Examples

      iex> get_story!(123)
      %Story{}

      iex> get_story!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_story!(String.t() | non_neg_integer) :: Story.t() | no_return
  def get_story!(id), do: Repo.get!(Story, id)

  @doc """
  Gets a story by its slug.

  ## Examples

      iex> get_story_by_slug("slug-234abfe")
      %Story{}

      iex> get_story_by_slug("slug-456a3be")
      nil

  """
  @spec get_story_by_slug(String.t()) :: Story.t() | nil
  def get_story_by_slug(slug) do
    slug
    |> String.split("-")
    |> List.last()
    |> get_story_by_unique_hash()
  end

  @doc """
  Gets a story by its unique_hash.

  ## Examples

      iex> get_story_by_unique_hash("a324b897c")
      %Story{}

      iex> get_story_by_unique_hash("jksdf234")
      nil

  """
  @spec get_story_by_unique_hash(String.t()) :: Story.t() | nil
  def get_story_by_unique_hash(unique_hash), do: get_story_by(unique_hash: unique_hash)

  @doc """
  Gets a story by given clauses.

  ## Examples

      iex> get_story_by(unique_hash: "abs2375cf")
      %Story{}

  """
  @spec get_story_by(Keyword.t()) :: Story.t() | nil
  def get_story_by(clauses), do: Repo.get_by(Story, clauses)

  @doc """
  Gets the title of a story.

  ## Examples

      iex> get_title(%Story{})
      "Title"

  """
  @spec get_title(Story.t()) :: String.t()
  def get_title(%Story{content: %{"blocks" => [%{"text" => title} | _]}}), do: title

  @doc """
  Gets the slug of a story.

  ## Examples

      iex> get_slug(%Story{})
      "title-abc123ba"

  """
  @spec get_slug(Story.t()) :: String.t()
  def get_slug(%Story{unique_hash: unique_hash} = story) do
    story
    |> Stories.get_title()
    |> Slugger.slugify_downcase()
    |> Kernel.<>("-")
    |> Kernel.<>(unique_hash)
  end

  @doc """
  Gets the author of a story.

  ## Examples

      iex> get_author(%Story{})
      %User{}

  """
  @spec get_author(Story.t()) :: User.t()
  def get_author(%Story{} = story) do
    story
    |> Story.preload_author()
    |> Map.get(:author)
  end

  @doc """
  Gets the tags of a story.

  ## Examples

      iex> get_tags(%Story{})
      [%Tag{}]

  """
  @spec get_tags(Story.t()) :: [Tag.t()]
  def get_tags(%Story{} = story) do
    story
    |> Story.preload_tags()
    |> Map.get(:tags)
  end

  @doc """
  Gets the publication of a story.

  ## Examples

      iex> get_publication(%Story{})
      %Publication{}

      iex> get_publication(%Story{})
      nil

  """
  @spec get_publication(Story.t()) :: Publication.t() | nil
  def get_publication(%Story{} = story) do
    story
    |> Story.preload_publication()
    |> Map.get(:publication)
  end

  @doc """
  Gets the word count of a story.

  ## Examples

      iex> get_word_count(%Story{})
      42

  """
  @spec get_word_count(Story.t()) :: non_neg_integer
  def get_word_count(%Story{content: %{"blocks" => blocks}}) do
    blocks
    |> Enum.map_join(" ", &Map.get(&1, "text"))
    |> String.split()
    |> length()
  end

  @doc """
  Gets the read time of a story in minutes.

  ## Examples

      iex> get_read_time(%Story{})
      12

  """
  @spec get_read_time(Story.t()) :: non_neg_integer
  def get_read_time(%Story{} = story) do
    avg_wpm = 275

    story
    |> get_word_count()
    |> div(avg_wpm)
    |> case do
      0 -> 1
      read_time -> read_time
    end
  end

  @doc """
  Gets the story count.

  ## Examples

      iex> get_story_count()
      815

  """
  @spec get_story_count :: non_neg_integer
  def get_story_count do
    query =
      from(
        s in Story,
        join: u in assoc(s, :author),
        where: is_nil(u.deactivated_at),
        select: count(s.id)
      )

    Repo.one!(query)
  end

  @doc """
  Returns `true` if the story has been published.
  `false` otherwise.

  ## Examples

      iex> has_been_published(%Story{})
      false

  """
  @spec has_been_published?(Story.t()) :: boolean
  def has_been_published?(%Story{published_at: published_at}),
    do: published_at <= NaiveDateTime.utc_now()

  @doc """
  Returns `true` if the story is public,
  `false` otherwise.

  ## Examples

      iex> public?(%Story{})
      true

      iex> public?(%Story{})
      false

      iex> public?(nil)
      false

  """
  @spec public?(Story.t()) :: boolean
  def public?(%Story{audience: :all} = story), do: has_been_published?(story)
  def public?(_), do: false

  @doc """
  Returns `true` if the user can see the story.
  `false` otherwise.

  ## Examples

      iex> story_public?(%Story{})
      true

      iex> story_public?(123)
      false

      iex> story_public?(nil)
      false

  """
  @spec can_see_story?(Story.t(), User.t()) :: boolean
  def can_see_story?(%Story{author_id: author_id}, %User{id: author_id}), do: true

  def can_see_story?(%Story{publication_id: publication_id}, %User{id: user_id})
      when not is_nil(publication_id) do
    Publications.can_edit_stories?(publication_id, user_id)
  end

  def can_see_story?(%Story{audience: :members} = story, %User{} = user) do
    is_member = Accounts.member?(user)
    has_been_published = has_been_published?(story)

    is_member and has_been_published
  end

  def can_see_story?(%Story{} = story, _user), do: public?(story)

  @doc """
  Returns `true` if the user can update the story,
  `false` otherwise.
  """
  @spec can_update_story?(Story.t(), User.t()) :: boolean
  def can_update_story?(%Story{author_id: author_id}, %User{id: author_id}), do: true

  def can_update_story?(%Story{publication_id: publication_id}, %User{id: user_id})
      when not is_nil(publication_id) do
    Publications.can_edit_stories?(publication_id, user_id)
  end

  def can_update_story?(_, _), do: false

  @spec can_delete_story?(Story.t(), User.t()) :: boolean
  def can_delete_story?(%Story{author_id: author_id}, %User{id: author_id}), do: true
  def can_delete_story?(_, _), do: false

  @doc """
  Inserts a story.
  """
  @spec insert_story(any) :: {:ok, any} | {:error, any, any, any}
  def insert_story(attrs) do
    Multi.new()
    |> maybe_insert_tags(attrs)
    |> insert_story(attrs)
    |> Repo.transaction()
  end

  defp insert_story(multi, attrs) do
    insert_story_fn = fn changes ->
      maybe_put_tags = fn attrs ->
        case changes do
          %{tags: tags} -> Map.put(attrs, :tags, tags)
          _ -> attrs
        end
      end

      attrs
      |> maybe_put_tags.()
      |> Story.changeset()
      |> Repo.insert()
    end

    Multi.run(multi, :story, insert_story_fn)
  end

  @doc """
  Updates a story.
  """
  @spec update_story(Story.t(), any) :: {:ok, any} | {:error, any, any, any}
  def update_story(%Story{} = story, attrs) do
    Multi.new()
    |> maybe_insert_tags(attrs)
    |> update_story(story, attrs)
    |> Repo.transaction()
  end

  defp update_story(multi, %Story{} = story, attrs) do
    update_story_fn = fn changes ->
      maybe_put_tags = fn {story, attrs} ->
        case changes do
          %{tags: tags} -> {Repo.preload(story, :tags), Map.put(attrs, :tags, tags)}
          _ -> {story, attrs}
        end
      end

      {story, attrs} = maybe_put_tags.({story, attrs})

      story
      |> Story.update_changeset(attrs)
      |> Repo.update()
    end

    Multi.run(multi, :story, update_story_fn)
  end

  defp maybe_insert_tags(multi, %{tags: tags}) do
    insert_tags_fn = fn _ -> {:ok, Tags.insert_and_get_all_tags(tags)} end

    Multi.run(multi, :tags, insert_tags_fn)
  end

  defp maybe_insert_tags(multi, _attrs), do: multi

  @doc """
  Removes a story from its publication.
  """
  @spec remove_from_publication(Story.t()) :: Story.t()
  def remove_from_publication(%Story{} = story) do
    attrs = %{publication_id: nil}

    update_story(story, attrs)
  end

  @doc """
  Deletes a story.
  """
  @spec delete_story(Story.t()) :: {:ok, Story.t()} | {:error, Ecto.Changeset.t()}
  def delete_story(%Story{} = story), do: Repo.delete(story)
end
