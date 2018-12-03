require 'rails_helper'
require 'support/use_stripe_mock'

describe Api::GraphqlController, type: :request do
  describe 'seller_accept_offer mutation' do
    include_context 'GraphQL Client'
    let(:order_seller_id) { jwt_partner_ids.first }
    let(:order_buyer_id) { jwt_user_id }
    let(:order) { Fabricate(:order, state: order_state, seller_id: order_seller_id, seller_type: 'gallery', buyer_id: order_buyer_id, buyer_type: 'user') }
    let(:offer) { Fabricate(:offer, order: order, from_id: order_buyer_id, from_type: 'user') }
    let(:order_state) { Order::SUBMITTED }

    let(:mutation) do
      <<-GRAPHQL
        mutation($input: SellerAcceptOfferInput!) {
          sellerAcceptOffer(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  state
                }
              }
              ... on OrderWithMutationFailure {
                error {
                  code
                  data
                  type
                }
              }
            }
          }
        }
      GRAPHQL
    end

    let(:seller_accept_offer_input) do
      {
        input: {
          offerId: offer.id.to_s
        }
      }
    end

    before do
      order.update!(last_offer: offer)
    end

    context 'when not in the submitted state' do
      let(:order_state) { Order::PENDING }

      it "returns invalid state transition error and doesn't change the order state" do
        response = client.execute(mutation, seller_accept_offer_input)

        expect(response.data.seller_accept_offer.order_or_error.error.type).to eq 'validation'
        expect(response.data.seller_accept_offer.order_or_error.error.code).to eq 'invalid_state'
        expect(order.reload.state).to eq Order::PENDING
      end
    end

    context 'when attempting to accept not the last offer' do
      it 'returns a validation error and does not change the order state' do
        create_order_and_original_offer
        create_another_offer

        response = client.execute(mutation, seller_accept_offer_input)

        expect(response.data.seller_accept_offer.order_or_error.error.type).to eq 'validation'
        expect(response.data.seller_accept_offer.order_or_error.error.code).to eq 'not_last_offer'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'with user without permission to this partner' do
      let(:order_seller_id) { 'another-partner-id' }

      it 'returns permission error' do
        response = client.execute(mutation, seller_accept_offer_input)

        expect(response.data.seller_accept_offer.order_or_error.error.type).to eq 'validation'
        expect(response.data.seller_accept_offer.order_or_error.error.code).to eq 'not_found'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'offer from seller' do
      let(:offer) { Fabricate(:offer, order: order, from_id: order_seller_id, from_type: 'gallery') }

      it 'returns permission error' do
        response = client.execute(mutation, seller_accept_offer_input)

        expect(response.data.seller_accept_offer.order_or_error.error.type).to eq 'validation'
        expect(response.data.seller_accept_offer.order_or_error.error.code).to eq 'cannot_accept_offer'
        expect(order.reload.state).to eq Order::SUBMITTED
      end
    end

    context 'when the specified offer does not exist' do
      let(:seller_accept_offer_input) do
        {
          input: {
            offerId: '-1'
          }
        }
      end

      it 'returns a not-found error' do
        expect { client.execute(mutation, seller_accept_offer_input) }.to raise_error do |error|
          expect(error.status_code).to eq(404)
        end
      end
    end

    context 'with proper permission' do
      it 'approves the order' do
        expect do
          client.execute(mutation, seller_accept_offer_input)
        end.to change { order.reload.state }.from(Order::SUBMITTED).to(Order::APPROVED)
      end
    end
  end

  def create_order_and_original_offer
    order
    offer
  end

  def create_another_offer
    another_offer = Fabricate(:offer, order: order)
    order.update!(last_offer: another_offer)
  end
end