defmodule NewRelic.Error.Trace do
  defstruct timestamp: nil,
            transaction_name: "",
            message: nil,
            expected: false,
            error_type: nil,
            cat_guid: "",
            stack_trace: nil,
            agent_attributes: %{},
            user_attributes: %{}

  @moduledoc false

  def format_errors(errors) do
    Enum.map(errors, &format_error/1)
  end

  @intrinsics [:traceId, :guid]
  defp format_error(%__MODULE__{} = error) do
    {intrinsics, user_attributes} = Map.split(error.user_attributes, @intrinsics)

    [
      error.timestamp,
      error.transaction_name,
      error.message,
      error.error_type,
      %{
        stack_trace: error.stack_trace,
        agentAttributes: format_agent_attributes(error.agent_attributes),
        userAttributes: format_user_attributes(user_attributes),
        intrinsics: Map.put(intrinsics, :"error.expected", error.expected)
      },
      error.cat_guid
    ]
  end

  defp format_agent_attributes(%{request_uri: request_uri}) do
    %{request_uri: request_uri}
  end

  defp format_agent_attributes(_agent_attributes) do
    %{}
  end

  defp format_user_attributes(user_attributes) do
    Map.new(user_attributes, fn {k, v} ->
      (String.Chars.impl_for(v) && {k, v}) || {k, inspect(v)}
    end)
  end
end
