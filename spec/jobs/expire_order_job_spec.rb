require 'rails_helper'
require 'timecop'

describe ExpireOrderJob, type: :job do
  let(:order) { Fabricate(:order) }
  describe '#perform' do
    before do
      allow(OrderService).to receive(:abandon!)
      allow(OrderService).to receive(:reject!)
    end

    context 'with an expired order' do
      it 'transitions a pending order to abandoned' do
        Timecop.freeze(order.state_expires_at + 1.second) do
          ExpireOrderJob.perform_now(order.id, Order::PENDING)
          expect(OrderService).to have_received(:abandon!).with(order)
        end
      end
      it 'transitions a submitted order to rejected' do
        order.update!(state: Order::SUBMITTED)
        Timecop.freeze(order.state_expires_at + 1.second) do
          ExpireOrderJob.perform_now(order.id, Order::SUBMITTED)
          expect(OrderService).to have_received(:reject!).with(order)
        end
      end
      it 'transitions an approved order to rejected' do
        order.update!(state: Order::APPROVED)
        Timecop.freeze(order.state_expires_at + 1.second) do
          ExpireOrderJob.perform_now(order.id, Order::APPROVED)
          expect(OrderService).to have_received(:reject!).with(order)
        end
      end
    end
    context 'with an order in a different state than when the job was made' do
      it 'does nothing' do
        order.update!(state: Order::SUBMITTED)
        Timecop.freeze(order.state_expires_at + 1.second) do
          ExpireOrderJob.perform_now(order.id, Order::PENDING)
          expect(OrderService).to_not have_received(:abandon!)
          expect(OrderService).to_not have_received(:reject!)
        end
      end
    end
    context 'with an order in the same state before its expiration time' do
      it 'does nothing' do
        ExpireOrderJob.perform_now(order.id, Order::PENDING)
        expect(OrderService).to_not have_received(:abandon!)
        expect(OrderService).to_not have_received(:reject!)
      end
    end
  end
end